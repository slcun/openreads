"""Tests for the filesystem-backed cover cache."""

import time
from pathlib import Path

import pytest

from douban_isbn_proxy.cover_cache import CoverCache


def test_cache_miss_returns_none(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    assert cache.get("9780306406157") is None


def test_cache_put_and_get_round_trip(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/jpeg", b"fake-image-bytes")
    result = cache.get("9780306406157")
    assert result is not None
    assert result.content_type == "image/jpeg"
    assert result.body == b"fake-image-bytes"


def test_cache_derives_extension_from_content_type(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/jpeg", b"data")
    png = tmp_path / "9780306406157.jpg"
    assert png.exists()


def test_cache_uses_png_extension(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/png", b"data")
    png = tmp_path / "9780306406157.png"
    assert png.exists()


def test_cache_uses_webp_extension(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/webp", b"data")
    png = tmp_path / "9780306406157.webp"
    assert png.exists()


def test_cache_falls_back_to_bin_for_unknown_type(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "application/octet-stream", b"data")
    assert (tmp_path / "9780306406157.bin").exists()


def test_cache_returns_etag(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/jpeg", b"data")
    result = cache.get("9780306406157")
    assert result is not None
    assert result.etag is not None
    assert isinstance(result.etag, str)
    assert len(result.etag) > 0
    # Same content should produce the same etag
    result2 = cache.get("9780306406157")
    assert result2 is not None
    assert result.etag == result2.etag


def test_cache_expiry_returns_none(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=0)
    cache.put("9780306406157", "image/jpeg", b"data")
    # TTL 0 means the entry is immediately expired
    assert cache.get("9780306406157") is None


def test_cache_atomic_write_does_not_create_partial_file(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    # Simulate a write that would be interrupted by using a context
    # where the temp file should not remain after a failed write.
    # We test that the final file is only present after successful put.
    cache.put("9780306406157", "image/jpeg", b"complete-data")
    result = cache.get("9780306406157")
    assert result is not None
    assert result.body == b"complete-data"
    # No .tmp files should remain
    tmp_files = list(tmp_path.glob("*.tmp"))
    assert len(tmp_files) == 0


def test_cache_miss_on_different_isbn(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/jpeg", b"data")
    assert cache.get("9780000000000") is None


def test_cache_file_path_format(tmp_path):
    cache = CoverCache(tmp_path, ttl_seconds=300)
    cache.put("9780306406157", "image/jpeg", b"data")
    expected = tmp_path / "9780306406157.jpg"
    assert expected.exists()
