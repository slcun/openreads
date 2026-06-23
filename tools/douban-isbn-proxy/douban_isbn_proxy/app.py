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
    def __init__(
        self,
        cache: SqliteCache,
        client: httpx.AsyncClient,
        minimum_request_interval_seconds: float,
        request_timeout_seconds: float,
    ):
        self._cache = cache
        self._client = client
        self._min_interval = minimum_request_interval_seconds
        self._timeout = request_timeout_seconds
        self._lock = asyncio.Lock()
        self._last_request_time = 0.0

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
        search_url = f"https://book.douban.com/subject_search?search_text={isbn}"
        try:
            search_resp = await self._client.get(search_url, timeout=self._timeout)
            search_resp.raise_for_status()
            search_html = search_resp.text
        except httpx.HTTPError as e:
            raise UpstreamError("upstream request failed") from e
        finally:
            # Advance clock even on errors to protect upstream from rapid retries
            self._last_request_time = time.monotonic()

        candidate_urls = parse_search_html(search_html)

        if not candidate_urls:
            logger.info("no candidates for isbn=%s", isbn)
            self._cache.put_not_found(isbn)
            return None

        for url in candidate_urls:
            try:
                detail_resp = await self._client.get(url, timeout=self._timeout)
                detail_resp.raise_for_status()
                detail_html = detail_resp.text
            except httpx.HTTPError as e:
                raise UpstreamError("upstream request failed") from e
            finally:
                # Advance clock even on errors to protect upstream from rapid retries
                self._last_request_time = time.monotonic()

            metadata = parse_detail_html(detail_html, isbn)
            if metadata is not None:
                logger.info("found match for isbn=%s source_id=%s", isbn, metadata.source_id)
                self._cache.put_success(metadata)
                return metadata

        logger.info("no matching edition for isbn=%s", isbn)
        self._cache.put_not_found(isbn)
        return None

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
