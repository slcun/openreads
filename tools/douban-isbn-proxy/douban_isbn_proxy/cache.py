import json
import sqlite3
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from douban_isbn_proxy.models import BookMetadata


@dataclass(frozen=True)
class CacheEntry:
    kind: str  # "success" or "not_found"
    payload: BookMetadata | None = None

    @staticmethod
    def not_found() -> "CacheEntry":
        return CacheEntry(kind="not_found")

    @staticmethod
    def success(metadata: BookMetadata) -> "CacheEntry":
        return CacheEntry(kind="success", payload=metadata)


class SqliteCache:
    def __init__(
        self,
        db_path: str | Path,
        ttl_seconds: int = 86400,
        clock: Callable[[], float] | None = None,
    ):
        self._ttl = ttl_seconds
        self._clock = clock or (lambda: __import__("time").time())
        self._conn = sqlite3.connect(str(db_path))
        self._conn.execute(
            """CREATE TABLE IF NOT EXISTS isbn_cache (
                isbn TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                payload_json TEXT,
                expires_at INTEGER NOT NULL
            )"""
        )
        self._conn.commit()

    def get(self, isbn: str) -> CacheEntry | None:
        row = self._conn.execute(
            "SELECT kind, payload_json, expires_at FROM isbn_cache WHERE isbn = ?",
            (isbn,),
        ).fetchone()
        if row is None:
            return None
        kind, payload_json, expires_at = row
        now = int(self._clock())
        if expires_at <= now:
            self._conn.execute("DELETE FROM isbn_cache WHERE isbn = ?", (isbn,))
            self._conn.commit()
            return None
        if kind == "not_found":
            return CacheEntry.not_found()
        payload = json.loads(payload_json) if payload_json else {}
        return CacheEntry.success(BookMetadata(**payload))

    def put_success(self, metadata: BookMetadata) -> None:
        expires_at = int(self._clock()) + self._ttl
        self._conn.execute(
            "INSERT OR REPLACE INTO isbn_cache (isbn, kind, payload_json, expires_at) VALUES (?, ?, ?, ?)",
            (metadata.isbn, "success", _to_json(metadata), expires_at),
        )
        self._conn.commit()

    def put_not_found(self, isbn: str) -> None:
        expires_at = int(self._clock()) + self._ttl
        self._conn.execute(
            "INSERT OR REPLACE INTO isbn_cache (isbn, kind, payload_json, expires_at) VALUES (?, ?, ?, ?)",
            (isbn, "not_found", None, expires_at),
        )
        self._conn.commit()


def _to_json(metadata: BookMetadata) -> str:
    d: dict[str, Any] = {
        "title": metadata.title,
        "isbn": metadata.isbn,
        "source_id": metadata.source_id,
    }
    if metadata.authors:
        d["authors"] = metadata.authors
    if metadata.cover_url is not None:
        d["cover_url"] = metadata.cover_url
    if metadata.publisher is not None:
        d["publisher"] = metadata.publisher
    if metadata.publication_year is not None:
        d["publication_year"] = metadata.publication_year
    if metadata.page_count is not None:
        d["page_count"] = metadata.page_count
    if metadata.description is not None:
        d["description"] = metadata.description
    if metadata.rating is not None:
        d["rating"] = metadata.rating
    if metadata.rating_count is not None:
        d["rating_count"] = metadata.rating_count
    return json.dumps(d)
