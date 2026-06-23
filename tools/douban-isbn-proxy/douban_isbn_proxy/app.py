import asyncio
import logging
import math
import time
from typing import NoReturn

import httpx
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel

from douban_isbn_proxy.cache import SqliteCache
from douban_isbn_proxy.config import Settings
from douban_isbn_proxy.douban import parse_detail_html, parse_search_html
from douban_isbn_proxy.isbn import normalize_isbn
from douban_isbn_proxy.models import BookMetadata

logger = logging.getLogger("douban_isbn_proxy")


class BookResponse(BaseModel):
    title: str | None = None
    authors: list[str] = []
    isbn: str
    cover_url: str | None = None
    publisher: str | None = None
    publication_year: int | None = None
    page_count: int | None = None
    description: str | None = None
    source_id: str | None = None
    rating: float | None = None
    rating_count: int | None = None

    @classmethod
    def from_metadata(cls, m: BookMetadata) -> "BookResponse":
        return cls(
            title=m.title,
            authors=m.authors,
            isbn=m.isbn,
            cover_url=m.cover_url,
            publisher=m.publisher,
            publication_year=m.publication_year,
            page_count=m.page_count,
            description=m.description,
            source_id=m.source_id,
            rating=m.rating,
            rating_count=m.rating_count,
        )


class ServiceUnavailable(Exception):
    pass


class UpstreamError(Exception):
    pass


class PacingError(Exception):
    def __init__(self, retry_after: int):
        self.retry_after = retry_after
        super().__init__(retry_after)


class DoubanLookup:
    _BASE_HEADERS: dict[str, str] = {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Accept-Encoding": "gzip, deflate, br",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
        "Sec-Fetch-User": "?1",
        "Upgrade-Insecure-Requests": "1",
        "sec-ch-ua": '"Not/A)Brand";v="99", "Google Chrome";v="127", "Chromium";v="127"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"Windows"',
    }

    def __init__(
        self,
        cache: SqliteCache,
        client: httpx.AsyncClient,
        minimum_request_interval_seconds: float,
        request_timeout_seconds: float,
        user_agent: str = "",
        cookie: str = "",
    ):
        self._cache = cache
        self._client = client
        self._min_interval = minimum_request_interval_seconds
        self._timeout = request_timeout_seconds
        self._user_agent = user_agent
        self._cookie = cookie
        self._lock = asyncio.Lock()
        self._last_request_time = 0.0
        self._search_url = ""

    async def lookup(self, isbn: str) -> BookMetadata | None:
        entry = self._cache.get(isbn)
        if entry is not None:
            logger.info("cache hit for isbn=%s kind=%s", isbn, entry.kind)
            return None if entry.kind == "not_found" else entry.payload

        async with self._lock:
            entry = self._cache.get(isbn)
            if entry is not None:
                logger.info("cache hit (double-check) for isbn=%s kind=%s", isbn, entry.kind)
                return None if entry.kind == "not_found" else entry.payload

            now = time.monotonic()
            elapsed = now - self._last_request_time
            if elapsed < self._min_interval:
                retry_after = math.ceil(self._min_interval - elapsed)
                logger.info("pacing limit for isbn=%s retry_after=%d", isbn, retry_after)
                raise PacingError(retry_after)

            logger.info("looking up isbn=%s", isbn)
            metadata = await self._fetch_book(isbn)
            return metadata

    async def _fetch_book(self, isbn: str) -> BookMetadata | None:
        search_url = (
            "https://search.douban.com/book/subject_search?"
            f"search_text={isbn}&cat=1001"
        )
        self._search_url = search_url
        search_html = await self._request_upstream(search_url)

        candidate_urls = parse_search_html(search_html)

        if not candidate_urls:
            logger.info("no candidates for isbn=%s", isbn)
            self._cache.put_not_found(isbn)
            return None

        for url in candidate_urls:
            detail_html = await self._request_upstream(url)
            try:
                metadata = parse_detail_html(detail_html, isbn)
            except (AttributeError, TypeError, ValueError) as e:
                raise UpstreamError("upstream response could not be parsed") from e
            if metadata is not None:
                logger.info("found match for isbn=%s source_id=%s", isbn, metadata.source_id)
                self._cache.put_success(metadata)
                return metadata

        logger.info("no matching edition for isbn=%s", isbn)
        self._cache.put_not_found(isbn)
        return None

    def _build_headers(self, url: str) -> dict[str, str]:
        headers = dict(self._BASE_HEADERS)
        headers["User-Agent"] = self._user_agent
        if self._cookie:
            headers["Cookie"] = self._cookie
        if self._search_url and url != self._search_url:
            headers["Referer"] = self._search_url
        elif "search.douban.com" in url:
            headers["Referer"] = "https://www.douban.com/"
        return headers

    async def _request_upstream(self, url: str) -> str:
        elapsed = time.monotonic() - self._last_request_time
        if elapsed < self._min_interval:
            await asyncio.sleep(self._min_interval - elapsed)
        headers = self._build_headers(url)
        try:
            response = await self._client.get(url, headers=headers, timeout=self._timeout)
            response.raise_for_status()
            return response.text
        except httpx.HTTPError as e:
            raise UpstreamError("upstream request failed") from e
        finally:
            self._last_request_time = time.monotonic()

    def assert_ready(self) -> None:
        try:
            self._cache.ping()
        except Exception as e:
            raise ServiceUnavailable() from e


def create_app(settings: Settings, lookup: DoubanLookup) -> FastAPI:
    _ = settings  # reserved for future middleware/cors configuration
    app = FastAPI(title="Douban ISBN Proxy")

    @app.get("/v1/books/isbn/{isbn}", response_model=BookResponse)
    async def get_book(isbn: str) -> BookResponse:
        normalized = normalize_isbn(isbn)
        if normalized is None:
            raise HTTPException(status_code=422, detail="invalid isbn")
        try:
            result = await lookup.lookup(normalized)
        except UpstreamError:
            raise HTTPException(status_code=502, detail="upstream error")
        except PacingError as e:
            raise HTTPException(
                status_code=429,
                detail="rate limited",
                headers={"retry-after": str(e.retry_after)},
            )
        if result is None:
            raise HTTPException(status_code=404, detail="book not found")
        return BookResponse.from_metadata(result)

    @app.get("/healthz", status_code=204)
    async def healthz() -> Response:
        try:
            lookup.assert_ready()
        except ServiceUnavailable:
            raise HTTPException(status_code=503, detail="service unavailable")
        return Response(status_code=204)

    return app
