import asyncio
import logging
import math
import random
import time
from typing import NoReturn

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel

from douban_isbn_proxy.cache import SqliteCache
from douban_isbn_proxy.config import Settings
from douban_isbn_proxy.cover_cache import CoverCache
from douban_isbn_proxy.douban import parse_detail_html, parse_mobile_search_html
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
    def from_metadata(cls, m: BookMetadata, public_base_url: str = "") -> "BookResponse":
        cover_url = m.cover_url
        if m.cover_url and public_base_url:
            base = public_base_url.rstrip("/")
            cover_url = f"{base}/v1/covers/{m.isbn}"
        return cls(
            title=m.title,
            authors=m.authors,
            isbn=m.isbn,
            cover_url=cover_url,
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

    _DOUBANIO_SUFFIX = ".doubanio.com"

    _MOBILE_UA = (
        "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/127.0.6533.84 Mobile Safari/537.36"
    )

    def __init__(
        self,
        cache: SqliteCache,
        client: httpx.AsyncClient,
        minimum_request_interval_seconds: float,
        request_timeout_seconds: float,
        user_agent: str = "",
        cookie: str = "",
        cover_cache: CoverCache | None = None,
    ):
        self._cache = cache
        self._client = client
        self._min_interval = minimum_request_interval_seconds
        self._timeout = request_timeout_seconds
        self._user_agent = user_agent
        self._cookie = cookie
        self._cover_cache = cover_cache
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

            logger.info("looking up isbn=%s (cache miss)", isbn)
            metadata = await self._fetch_book(isbn)
            if metadata is None:
                logger.warning("lookup returned no result for isbn=%s", isbn)
            return metadata

    async def _fetch_book(self, isbn: str) -> BookMetadata | None:
        search_url = (
            f"https://m.douban.com/search/?query={isbn}&type=book"
        )
        self._search_url = search_url
        logger.info("fetching mobile search page for isbn=%s", isbn)
        search_html = await self._request_upstream(search_url, f"search isbn={isbn}")

        logger.info("parsing mobile search results for isbn=%s (html_len=%d)", isbn, len(search_html))
        candidate_urls = parse_mobile_search_html(search_html)

        if not candidate_urls:
            logger.warning(
                "no candidates found for isbn=%s. "
                "Possible causes: anti-crawl page, network issue, or ISBN not found. "
                "Suggest enabling DEBUG log level to inspect raw response.",
                isbn,
            )
            self._cache.put_not_found(isbn)
            return None

        logger.info("found %d candidate(s) for isbn=%s", len(candidate_urls), isbn)

        for idx, url in enumerate(candidate_urls):
            logger.info("fetching candidate #%d for isbn=%s", idx + 1, isbn)
            detail_html = await self._request_upstream(url, f"detail candidate#{idx + 1} isbn={isbn}")
            try:
                metadata = parse_detail_html(detail_html, isbn)
            except (AttributeError, TypeError, ValueError) as e:
                logger.warning(
                    "failed to parse candidate #%d for isbn=%s: %s",
                    idx + 1,
                    isbn,
                    e,
                )
                raise UpstreamError("upstream response could not be parsed") from e
            if metadata is not None:
                logger.info("found match for isbn=%s source_id=%s", isbn, metadata.source_id)
                self._cache.put_success(metadata)
                return metadata

        logger.warning(
            "all %d candidate(s) exhausted for isbn=%s. "
            "None matched the requested edition (ISBN mismatch on detail pages).",
            len(candidate_urls),
            isbn,
        )
        self._cache.put_not_found(isbn)
        return None

    def _build_headers(self, url: str) -> dict[str, str]:
        is_mobile = "m.douban.com" in url
        if is_mobile:
            headers = {
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                "Accept-Encoding": "gzip, deflate, br",
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
                "Sec-Fetch-User": "?1",
                "Upgrade-Insecure-Requests": "1",
                "sec-ch-ua": '"Google Chrome";v="127", "Not=A?Brand";v="99", "Chromium";v="127"',
                "sec-ch-ua-mobile": "?1",
                "sec-ch-ua-platform": '"Android"',
            }
            headers["User-Agent"] = self._MOBILE_UA
        else:
            headers = dict(self._BASE_HEADERS)
            headers["User-Agent"] = self._user_agent
        if self._cookie:
            headers["Cookie"] = self._cookie
        if self._search_url and url != self._search_url:
            headers["Referer"] = self._search_url
        elif "m.douban.com" in url:
            headers["Referer"] = "https://m.douban.com/"
        return headers

    async def _request_upstream(self, url: str, detail: str = "") -> str:
        elapsed = time.monotonic() - self._last_request_time
        if elapsed < self._min_interval:
            wait = self._min_interval - elapsed
            jitter = random.uniform(1.0, 1.5)
            total_wait = wait * jitter
            logger.debug("rate-limiting sleep %.2fs (base=%.2f, jitter=%.2fx) for %s", total_wait, wait, jitter, detail or url)
            await asyncio.sleep(total_wait)
        headers = self._build_headers(url)
        ctx = detail or url
        try:
            response = await self._client.get(url, headers=headers, timeout=self._timeout)
            response.raise_for_status()
            logger.debug("upstream ok (%d bytes) for %s", len(response.text), ctx)
            return response.text
        except httpx.TimeoutException as e:
            logger.warning("upstream timeout for %s: %s", ctx, e)
            raise UpstreamError("upstream request timed out") from e
        except httpx.HTTPStatusError as e:
            body_preview = e.response.text[:500] if e.response.text else ""
            logger.warning(
                "upstream HTTP %d for %s. Response preview: %.200s",
                e.response.status_code,
                ctx,
                body_preview.replace("\n", " "),
            )
            raise UpstreamError(f"upstream returned HTTP {e.response.status_code}") from e
        except httpx.HTTPError as e:
            logger.warning("upstream request failed for %s: %s [%s]", ctx, type(e).__name__, e)
            raise UpstreamError("upstream request failed") from e
        finally:
            self._last_request_time = time.monotonic()

    def assert_ready(self) -> None:
        try:
            self._cache.ping()
        except Exception as e:
            raise ServiceUnavailable() from e

    async def fetch_cover(self, isbn: str) -> tuple[bytes, str] | None:
        """Fetch a cover image for the given ISBN.

        Returns (image_bytes, content_type) or None if no cover is available.
        """
        logger.info("fetching cover for isbn=%s", isbn)
        entry = self._cache.get(isbn)
        if entry is not None and entry.kind == "success" and entry.payload is not None:
            metadata = entry.payload
        else:
            metadata = await self.lookup(isbn)
        if metadata is None:
            logger.warning("no metadata found for isbn=%s, cannot fetch cover", isbn)
            return None

        cover_url = metadata.cover_url
        if not cover_url:
            logger.warning("metadata for isbn=%s has no cover_url (source_id=%s)", isbn, metadata.source_id)
            return None

        parsed = httpx.URL(cover_url)
        if parsed.scheme != "https" or not parsed.host:
            logger.warning("invalid cover_url for isbn=%s: %s", isbn, cover_url)
            return None
        if not parsed.host.endswith(self._DOUBANIO_SUFFIX):
            logger.warning("rejected non-doubanio cover host: %s (isbn=%s)", parsed.host, isbn)
            return None

        headers = {
            "User-Agent": self._user_agent,
            "Referer": "https://book.douban.com/",
        }
        try:
            response = await self._client.get(
                cover_url,
                headers=headers,
                follow_redirects=False,
                timeout=self._timeout,
            )
            if response.status_code >= 300:
                logger.warning(
                    "cover fetch returned HTTP %d for isbn=%s url=%s",
                    response.status_code,
                    isbn,
                    cover_url,
                )
                return None
            content_type = response.headers.get("content-type", "")
            if not content_type.startswith("image/"):
                logger.warning(
                    "cover fetch returned non-image content-type='%s' for isbn=%s",
                    content_type,
                    isbn,
                )
                return None
            logger.info("cover fetched OK for isbn=%s (%d bytes, %s)", isbn, len(response.content), content_type)
            return response.content, content_type
        except httpx.TimeoutException as e:
            logger.warning("cover fetch timeout for isbn=%s: %s", isbn, e)
            raise UpstreamError("cover request timed out") from e
        except httpx.HTTPError as e:
            logger.warning("cover fetch failed for isbn=%s: %s [%s]", isbn, type(e).__name__, e)
            raise UpstreamError("cover request failed") from e


def create_app(settings: Settings, lookup: DoubanLookup) -> FastAPI:
    app = FastAPI(title="Douban ISBN Proxy")

    @app.get("/v1/books/isbn/{isbn}", response_model=BookResponse)
    async def get_book(isbn: str, request: Request) -> BookResponse:
        normalized = normalize_isbn(isbn)
        if normalized is None:
            logger.warning("invalid isbn format: %s", isbn)
            raise HTTPException(status_code=422, detail="invalid isbn")
        logger.info("book lookup request: isbn=%s", normalized)
        try:
            result = await lookup.lookup(normalized)
        except UpstreamError as e:
            logger.warning("upstream error for isbn=%s: %s", normalized, e)
            raise HTTPException(status_code=502, detail="upstream error")
        except PacingError as e:
            logger.info("rate limited for isbn=%s retry_after=%d", normalized, e.retry_after)
            raise HTTPException(
                status_code=429,
                detail="rate limited",
                headers={"retry-after": str(e.retry_after)},
            )
        if result is None:
            logger.warning("book not found: isbn=%s", normalized)
            raise HTTPException(status_code=404, detail="book not found")
        logger.info("book found: isbn=%s title=%s", normalized, result.title)
        public_base_url = settings.public_base_url or str(request.base_url).rstrip("/")
        return BookResponse.from_metadata(result, public_base_url=public_base_url)

    @app.get("/v1/covers/{isbn}")
    async def get_cover(isbn: str) -> Response:
        normalized = normalize_isbn(isbn)
        if normalized is None:
            logger.warning("invalid isbn for cover request: %s", isbn)
            raise HTTPException(status_code=422, detail="invalid isbn")

        cover_cache = lookup._cover_cache
        if cover_cache is not None:
            cached = cover_cache.get(normalized)
            if cached is not None:
                logger.info("cover cache hit for isbn=%s", normalized)
                return Response(
                    content=cached.body,
                    media_type=cached.content_type,
                    headers={
                        "Cache-Control": "public, max-age=86400",
                        "ETag": cached.etag,
                    },
                )

        logger.info("cover cache miss for isbn=%s, fetching upstream", normalized)
        try:
            result = await lookup.fetch_cover(normalized)
        except UpstreamError as e:
            logger.warning("upstream error fetching cover for isbn=%s: %s", normalized, e)
            raise HTTPException(status_code=502, detail="upstream error")
        except PacingError as e:
            logger.info("rate limited for cover isbn=%s retry_after=%d", normalized, e.retry_after)
            raise HTTPException(
                status_code=429,
                detail="rate limited",
                headers={"retry-after": str(e.retry_after)},
            )
        if result is None:
            logger.warning("cover not found for isbn=%s", normalized)
            raise HTTPException(status_code=404, detail="cover not found")

        body, content_type = result
        if cover_cache is not None:
            cover_cache.put(normalized, content_type, body)
            cached = cover_cache.get(normalized)
            etag = cached.etag if cached else ""
        else:
            etag = ""

        return Response(
            content=body,
            media_type=content_type,
            headers={
                "Cache-Control": "public, max-age=86400",
                "ETag": etag,
            },
        )

    @app.get("/healthz", status_code=204)
    async def healthz() -> Response:
        try:
            lookup.assert_ready()
        except ServiceUnavailable:
            raise HTTPException(status_code=503, detail="service unavailable")
        return Response(status_code=204)

    return app
