"""Tests for the FastAPI application layer."""

import logging
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from douban_isbn_proxy.cache import SqliteCache


def load_fixture(name: str) -> str:
    return (Path(__file__).parent / "fixtures" / name).read_text(encoding="utf-8")


class FakeUpstream:
    """Mock httpx transport returning pre-queued responses."""

    def __init__(self):
        self._queue: list[httpx.Response] = []
        self.request_count = 0

    def queue_search_and_detail(self, isbn: str) -> None:
        self._queue.append(httpx.Response(200, text=load_fixture("search.html")))
        self._queue.append(httpx.Response(200, text=load_fixture("detail_matching.html")))

    def queue_search_without_candidates(self) -> None:
        self._queue.append(
            httpx.Response(200, text="<html><body><div>No results</div></body></html>")
        )

    def _handler(self, request: httpx.Request) -> httpx.Response:
        self.request_count += 1
        if not self._queue:
            return httpx.Response(500, text="unexpected request")
        return self._queue.pop(0)


@pytest.fixture
def upstream():
    return FakeUpstream()


@pytest.fixture
def cache(tmp_path):
    return SqliteCache(tmp_path / "test.db", ttl_seconds=300, clock=lambda: 100)


def _make_client(upstream, cache, min_interval=0):
    from douban_isbn_proxy.app import DoubanLookup, create_app
    from douban_isbn_proxy.config import Settings

    transport = httpx.MockTransport(upstream._handler)
    async_client = httpx.AsyncClient(transport=transport)
    lookup = DoubanLookup(
        cache=cache,
        client=async_client,
        minimum_request_interval_seconds=min_interval,
        request_timeout_seconds=10,
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
    def test_returns_metadata_then_uses_cache(self, client, upstream):
        upstream.queue_search_and_detail("9780306406157")
        first = client.get("/v1/books/isbn/9780306406157")
        second = client.get("/v1/books/isbn/9780306406157")
        assert first.status_code == second.status_code == 200
        assert second.json()["source_id"] == "1234567"
        assert upstream.request_count == 2

    def test_returns_404_for_confirmed_absence(self, client, upstream):
        upstream.queue_search_without_candidates()
        assert client.get("/v1/books/isbn/9780306406157").status_code == 404

    def test_returns_429_and_retry_after_when_paced(self, paced_client, upstream):
        upstream.queue_search_and_detail("9780306406157")
        assert paced_client.get("/v1/books/isbn/9780306406157").status_code == 200
        response = paced_client.get("/v1/books/isbn/9781492056355")
        assert response.status_code == 429
        assert response.headers["retry-after"] == "2"

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
        )
        app = create_app(settings=Settings(), lookup=lookup)
        with TestClient(app) as c:
            response = c.get("/v1/books/isbn/9780306406157")
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
        )
        app = create_app(settings=Settings(), lookup=lookup)
        with TestClient(app) as c:
            response = c.get("/healthz")
            assert response.status_code == 503

    def test_log_contains_no_html_or_search_url(self, client, upstream, caplog):
        upstream.queue_search_and_detail("9780306406157")
        with caplog.at_level(logging.INFO):
            client.get("/v1/books/isbn/9780306406157")
        app_records = [r.message for r in caplog.records if r.name == "douban_isbn_proxy"]
        log_text = "\n".join(app_records)
        assert "<html" not in log_text
        assert "subject_search" not in log_text
