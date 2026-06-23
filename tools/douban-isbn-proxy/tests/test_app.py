"""Tests for the FastAPI application layer."""

import logging
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from douban_isbn_proxy.cache import SqliteCache
from douban_isbn_proxy.cover_cache import CoverCache


def load_fixture(name: str) -> str:
    return (Path(__file__).parent / "fixtures" / name).read_text(encoding="utf-8")


class FakeUpstream:
    """Mock httpx transport returning pre-queued responses."""

    def __init__(self):
        self._queue: list[httpx.Response] = []
        self.request_count = 0
        self.requested_urls: list[str] = []

    def queue_search_and_detail(self, isbn: str) -> None:
        self._queue.append(httpx.Response(200, text=load_fixture("search.html")))
        self._queue.append(httpx.Response(200, text=load_fixture("detail_matching.html")))

    def queue_search_without_candidates(self) -> None:
        self._queue.append(
            httpx.Response(200, text="<html><body><div>No results</div></body></html>")
        )

    def _handler(self, request: httpx.Request) -> httpx.Response:
        self.request_count += 1
        self.requested_urls.append(str(request.url))
        if not self._queue:
            return httpx.Response(500, text="unexpected request")
        return self._queue.pop(0)


@pytest.fixture
def upstream():
    return FakeUpstream()


@pytest.fixture
def cache(tmp_path):
    return SqliteCache(tmp_path / "test.db", ttl_seconds=300, clock=lambda: 100)


def _make_client(upstream, cache, min_interval=0, cover_cache=None):
    from douban_isbn_proxy.app import DoubanLookup, create_app
    from douban_isbn_proxy.config import Settings

    transport = httpx.MockTransport(upstream._handler)
    async_client = httpx.AsyncClient(transport=transport)
    lookup = DoubanLookup(
        cache=cache,
        client=async_client,
        minimum_request_interval_seconds=min_interval,
        request_timeout_seconds=10,
        user_agent="",
        cookie="",
        cover_cache=cover_cache,
    )
    app = create_app(settings=Settings(), lookup=lookup)
    return TestClient(app)


@pytest.fixture
def client(upstream, cache):
    with _make_client(upstream, cache, min_interval=0) as c:
        yield c


@pytest.fixture
def paced_client(upstream, cache):
    with _make_client(upstream, cache, min_interval=2) as c:
        yield c


class TestBookLookup:
    def test_derives_cover_url_from_the_book_request(self, client, upstream):
        upstream.queue_search_and_detail("9780306406157")

        response = client.get("/v1/books/isbn/9780306406157")

        assert response.status_code == 200
        assert response.json()["cover_url"] == (
            "http://testserver/v1/covers/9780306406157"
        )

    def test_returns_metadata_then_uses_cache(self, client, upstream):
        upstream.queue_search_and_detail("9780306406157")
        first = client.get("/v1/books/isbn/9780306406157")
        second = client.get("/v1/books/isbn/9780306406157")
        assert first.status_code == second.status_code == 200
        assert second.json()["source_id"] == "1234567"
        assert upstream.request_count == 2

    def test_uses_the_douban_book_search_endpoint(self, client, upstream):
        upstream.queue_search_and_detail("9780306406157")

        response = client.get("/v1/books/isbn/9780306406157")

        assert response.status_code == 200
        assert upstream.requested_urls[0] == (
            "https://m.douban.com/search/?query=9780306406157&type=book"
        )

    def test_returns_404_for_confirmed_absence(self, client, upstream):
        upstream.queue_search_without_candidates()
        assert client.get("/v1/books/isbn/9780306406157").status_code == 404

    def test_returns_429_and_retry_after_when_paced(self, paced_client, upstream):
        upstream.queue_search_and_detail("9780306406157")
        assert paced_client.get("/v1/books/isbn/9780306406157").status_code == 200
        response = paced_client.get("/v1/books/isbn/9781492056355")
        assert response.status_code == 429
        assert response.headers["retry-after"] == "2"

    def test_waits_between_search_and_detail_requests(self, upstream, cache, monkeypatch):
        sleeps = []

        async def record_sleep(delay):
            sleeps.append(delay)

        monkeypatch.setattr("douban_isbn_proxy.app.asyncio.sleep", record_sleep)
        upstream.queue_search_and_detail("9780306406157")
        with _make_client(upstream, cache, min_interval=2) as client:
            response = client.get("/v1/books/isbn/9780306406157")

        assert response.status_code == 200
        assert sleeps
        assert sleeps[0] > 0

    def test_invalid_isbn_returns_422(self, client):
        response = client.get("/v1/books/isbn/not-an-isbn")
        assert response.status_code == 422

    def test_upstream_connection_failure_returns_502(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        def fail_handler(request):
            raise httpx.ConnectError("connection refused")

        transport = httpx.MockTransport(fail_handler)
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)
        with TestClient(app) as c:
            response = c.get("/v1/books/isbn/9780306406157")
            assert response.status_code == 502

    def test_parser_failure_returns_502(self, cache, upstream, monkeypatch):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        def fail_parser(html, isbn):
            raise ValueError("unexpected upstream markup")

        monkeypatch.setattr("douban_isbn_proxy.app.parse_detail_html", fail_parser)
        upstream.queue_search_and_detail("9780306406157")
        transport = httpx.MockTransport(upstream._handler)
        lookup = DoubanLookup(
            cache=cache,
            client=httpx.AsyncClient(transport=transport),
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.get("/v1/books/isbn/9780306406157")

        assert response.status_code == 502

    def test_healthz_returns_204_when_ready(self, client):
        assert client.get("/healthz").status_code == 204

    def test_healthz_returns_503_when_cache_unavailable(self, tmp_path, monkeypatch):
        from douban_isbn_proxy.app import DoubanLookup, ServiceUnavailable, create_app
        from douban_isbn_proxy.config import Settings

        cache = SqliteCache(tmp_path / "test.db", ttl_seconds=300, clock=lambda: 100)

        def broken_ping():
            raise RuntimeError("cache unavailable")

        monkeypatch.setattr(cache, "ping", broken_ping)
        transport = httpx.MockTransport(lambda r: httpx.Response(200))
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)
        with TestClient(app) as c:
            response = c.get("/healthz")
            assert response.status_code == 503

    def test_sends_user_agent_header(self, upstream, cache):
        from douban_isbn_proxy.app import DoubanLookup, Settings, create_app

        captured = {}

        def capture_handler(request: httpx.Request) -> httpx.Response:
            if "ua" not in captured:
                captured["ua"] = request.headers.get("user-agent", "")
            return httpx.Response(200, text=load_fixture("search.html"))

        transport = httpx.MockTransport(capture_handler)
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="TestBot/1.0",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)
        with TestClient(app) as c:
            c.get("/v1/books/isbn/9780306406157")

        # Mobile UA is used for m.douban.com search requests
        ua = captured.get("ua", "")
        assert ua != ""
        assert "Mobile" in ua

    def test_sends_browser_like_headers(self, upstream, cache):
        from douban_isbn_proxy.app import DoubanLookup, Settings, create_app

        captured = {}

        def capture_handler(request: httpx.Request) -> httpx.Response:
            if "headers" not in captured:
                captured["headers"] = dict(request.headers)
            return httpx.Response(200, text=load_fixture("search.html"))

        transport = httpx.MockTransport(capture_handler)
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="Mozilla/5.0 Test Chrome/127",
            cookie="bid=abc123",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)
        with TestClient(app) as c:
            c.get("/v1/books/isbn/9780306406157")

        headers = captured.get("headers", {})
        assert headers.get("user-agent") is not None
        assert headers.get("cookie") == "bid=abc123"
        assert headers.get("accept") is not None
        assert headers.get("accept-language") is not None
        assert "sec-ch-ua" in headers
        assert headers.get("sec-fetch-dest") == "document"
        assert headers.get("referer") is not None
        # Mobile headers when searching via m.douban.com
        assert headers.get("sec-ch-ua-mobile") == "?1"
        assert headers.get("sec-ch-ua-platform") == '"Android"'

    def test_log_contains_no_html_or_search_url(self, client, upstream, caplog):
        upstream.queue_search_and_detail("9780306406157")
        with caplog.at_level(logging.INFO):
            client.get("/v1/books/isbn/9780306406157")
        app_records = [r.message for r in caplog.records if r.name == "douban_isbn_proxy"]
        log_text = "\n".join(app_records)
        assert "<html" not in log_text
        assert "subject_search" not in log_text
        assert "m.douban.com/search" not in log_text


class TestCoverFetch:
    def test_preserves_direct_cover_url_without_public_base_url(self):
        from douban_isbn_proxy.app import BookResponse
        from douban_isbn_proxy.models import BookMetadata

        metadata = BookMetadata(
            title="Test Book",
            isbn="9780306406157",
            source_id="1234567",
            cover_url="https://img1.doubanio.com/view/subject/l/public/s1234567.jpg",
        )

        assert BookResponse.from_metadata(metadata).cover_url == metadata.cover_url

    def _seed_cover_metadata(self, cache, isbn="9780306406157", cover_url="https://img1.doubanio.com/view/subject/l/public/s1234567.jpg"):
        from douban_isbn_proxy.models import BookMetadata
        meta = BookMetadata(
            title="Test Book",
            isbn=isbn,
            source_id="1234567",
            cover_url=cover_url,
        )
        cache.put_success(meta)

    def test_fetches_doubanio_cover_with_referer(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache)

        captured = {}

        def capture_handler(request: httpx.Request) -> httpx.Response:
            captured["referer"] = request.headers.get("referer", "")
            captured["user_agent"] = request.headers.get("user-agent", "")
            return httpx.Response(200, content=b"fake-image", headers={"content-type": "image/jpeg"})

        transport = httpx.MockTransport(capture_handler)
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="TestBot/1.0",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 200
        assert response.content == b"fake-image"
        assert response.headers["content-type"] == "image/jpeg"
        assert captured["referer"] == "https://book.douban.com/"
        assert captured["user_agent"] == "TestBot/1.0"

    def test_rejects_non_doubanio_host(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache, cover_url="https://evil.example.com/image.jpg")

        transport = httpx.MockTransport(lambda r: httpx.Response(200, content=b"image", headers={"content-type": "image/jpeg"}))
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 404

    def test_rejects_non_image_response(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache)

        transport = httpx.MockTransport(lambda r: httpx.Response(200, content=b"<html>not an image</html>", headers={"content-type": "text/html"}))
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 404

    def test_rejects_redirect(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache)

        transport = httpx.MockTransport(lambda r: httpx.Response(302, headers={"location": "https://evil.example.com/virus.exe"}))
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 404

    def test_cache_hit_returns_cached_image(self, cache, tmp_path):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache)
        cover_cache = CoverCache(tmp_path / "cover_cache", ttl_seconds=300)
        cover_cache.put("9780306406157", "image/jpeg", b"cached-image")

        upstream_hit = []

        def fail_if_called(request):
            upstream_hit.append(True)
            return httpx.Response(500)

        transport = httpx.MockTransport(fail_if_called)
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=cover_cache,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 200
        assert response.content == b"cached-image"
        assert upstream_hit == []

    def test_cache_miss_fetches_and_caches(self, cache, tmp_path):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache)
        cover_cache = CoverCache(tmp_path / "cover_cache", ttl_seconds=300)

        fetch_count = []

        def fetch_handler(request):
            fetch_count.append(True)
            return httpx.Response(200, content=b"fresh-image", headers={"content-type": "image/jpeg"})

        transport = httpx.MockTransport(fetch_handler)
        async_client = httpx.AsyncClient(transport=transport)
        lookup = DoubanLookup(
            cache=cache,
            client=async_client,
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=cover_cache,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 200
        assert response.content == b"fresh-image"
        assert len(fetch_count) == 1

        # Second request should be served from cache
        response2 = c.get("/v1/covers/9780306406157")
        assert response2.status_code == 200
        assert response2.content == b"fresh-image"
        assert len(fetch_count) == 1

    def test_invalid_isbn_returns_422(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        lookup = DoubanLookup(
            cache=cache,
            client=httpx.AsyncClient(),
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/not-an-isbn")

        assert response.status_code == 422

    def test_no_cover_in_metadata_returns_404(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings
        from douban_isbn_proxy.models import BookMetadata

        meta = BookMetadata(
            title="No Cover",
            isbn="9780306406157",
            source_id="1234567",
            cover_url=None,
        )
        cache.put_success(meta)

        lookup = DoubanLookup(
            cache=cache,
            client=httpx.AsyncClient(),
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            user_agent="",
            cookie="",
            cover_cache=None,
        )
        app = create_app(settings=Settings(), lookup=lookup)

        with TestClient(app) as c:
            response = c.get("/v1/covers/9780306406157")

        assert response.status_code == 404

    def test_upstream_cover_failure_returns_502(self, cache):
        from douban_isbn_proxy.app import DoubanLookup, create_app
        from douban_isbn_proxy.config import Settings

        self._seed_cover_metadata(cache)

        def fail_handler(request):
            raise httpx.ConnectError("connection refused")

        lookup = DoubanLookup(
            cache=cache,
            client=httpx.AsyncClient(transport=httpx.MockTransport(fail_handler)),
            minimum_request_interval_seconds=0,
            request_timeout_seconds=10,
            cover_cache=None,
        )
        with TestClient(create_app(Settings(), lookup)) as client:
            response = client.get("/v1/covers/9780306406157")

        assert response.status_code == 502
