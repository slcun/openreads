import hashlib
import os
import tempfile
import time as time_module
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CoverEntry:
    content_type: str
    body: bytes
    etag: str


_CONTENT_TYPE_EXTENSIONS: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/avif": ".avif",
}


class CoverCache:
    def __init__(
        self,
        cache_dir: str | Path,
        ttl_seconds: int = 86400,
        clock: Callable[[], float] | None = None,
    ):
        self._dir = Path(cache_dir)
        self._dir.mkdir(parents=True, exist_ok=True)
        self._ttl = ttl_seconds
        self._clock = clock or time_module.time

    def get(self, isbn: str) -> CoverEntry | None:
        path = self._find_file(isbn)
        if path is None:
            return None

        now = self._clock()
        if now - path.stat().st_mtime > self._ttl:
            path.unlink(missing_ok=True)
            return None

        content_type = self._content_type_for(path.suffix)
        body = path.read_bytes()
        etag = self._compute_etag(path)
        return CoverEntry(content_type=content_type, body=body, etag=etag)

    def put(self, isbn: str, content_type: str, body: bytes) -> None:
        ext = _CONTENT_TYPE_EXTENSIONS.get(content_type, ".bin")
        final_path = self._dir / f"{isbn}{ext}"

        fd, tmp_path_str = tempfile.mkstemp(dir=str(self._dir), suffix=".tmp")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(body)
            os.replace(tmp_path_str, str(final_path))
        except BaseException:
            try:
                os.unlink(tmp_path_str)
            except FileNotFoundError:
                pass
            raise

    def _find_file(self, isbn: str) -> Path | None:
        for ext in _CONTENT_TYPE_EXTENSIONS.values():
            path = self._dir / f"{isbn}{ext}"
            if path.exists():
                return path
        path = self._dir / f"{isbn}.bin"
        return path if path.exists() else None

    @staticmethod
    def _content_type_for(suffix: str) -> str:
        for ct, ext in _CONTENT_TYPE_EXTENSIONS.items():
            if ext == suffix:
                return ct
        return "application/octet-stream"

    @staticmethod
    def _compute_etag(path: Path) -> str:
        mtime = path.stat().st_mtime
        size = path.stat().st_size
        raw = hashlib.sha256(f"{mtime}:{size}".encode()).hexdigest()[:16]
        return f'"{raw}"'
