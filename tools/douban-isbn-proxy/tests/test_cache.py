from pathlib import Path

import pytest

from douban_isbn_proxy.cache import CacheEntry, SqliteCache


def load_fixture(name: str) -> str:
    return (Path(__file__).parent / "fixtures" / name).read_text(encoding="utf-8")


def test_cache_returns_unexpired_not_found_and_expires_it(tmp_path):
    cache = SqliteCache(tmp_path / "cache.db", ttl_seconds=60, clock=lambda: 100)
    cache.put_not_found("9780306406157")
    assert cache.get("9780306406157") == CacheEntry.not_found()
    expired = SqliteCache(tmp_path / "cache.db", ttl_seconds=60, clock=lambda: 161)
    assert expired.get("9780306406157") is None


def test_cache_round_trip_success(tmp_path):
    from douban_isbn_proxy.models import BookMetadata

    cache = SqliteCache(tmp_path / "cache.db", ttl_seconds=300, clock=lambda: 100)
    meta = BookMetadata(
        title="Test Book",
        isbn="9780306406157",
        source_id="1234567",
        authors=["Ada Author"],
    )
    cache.put_success(meta)
    entry = cache.get("9780306406157")
    assert entry is not None
    assert entry.kind == "success"
    assert entry.payload.title == "Test Book"


def test_cache_miss_returns_none(tmp_path):
    cache = SqliteCache(tmp_path / "cache.db", ttl_seconds=60, clock=lambda: 100)
    assert cache.get("9780000000000") is None
