import os
from dataclasses import dataclass, field


@dataclass
class Settings:
    bind_host: str = field(default_factory=lambda: os.getenv("BIND_HOST", "0.0.0.0"))
    bind_port: int = field(default_factory=lambda: int(os.getenv("BIND_PORT", "8000")))
    cache_path: str = field(default_factory=lambda: os.getenv("DOUBAN_PROXY_CACHE_PATH") or os.getenv("CACHE_PATH", "cache.db"))
    cache_ttl_seconds: int = field(default_factory=lambda: int(os.getenv("CACHE_TTL_SECONDS", "86400")))
    minimum_request_interval_seconds: float = field(
        default_factory=lambda: float(os.getenv("MINIMUM_REQUEST_INTERVAL_SECONDS", "2.0"))
    )
    request_timeout_seconds: float = field(
        default_factory=lambda: float(os.getenv("REQUEST_TIMEOUT_SECONDS", "30.0"))
    )
    cors_allow_origins: list[str] | None = field(default=None)
