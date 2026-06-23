import os
from dataclasses import dataclass, field


@dataclass
class Settings:
    bind_host: str = field(default_factory=lambda: os.getenv("BIND_HOST", "0.0.0.0"))
    bind_port: int = field(default_factory=lambda: int(os.getenv("BIND_PORT", "8080")))
    cache_path: str = field(default_factory=lambda: os.getenv("DOUBAN_PROXY_CACHE_PATH") or os.getenv("CACHE_PATH", "cache.db"))
    cache_ttl_seconds: int = field(default_factory=lambda: int(os.getenv("CACHE_TTL_SECONDS", "86400")))
    minimum_request_interval_seconds: float = field(
        default_factory=lambda: float(os.getenv("MINIMUM_REQUEST_INTERVAL_SECONDS", "2.0"))
    )
    request_timeout_seconds: float = field(
        default_factory=lambda: float(os.getenv("REQUEST_TIMEOUT_SECONDS", "30.0"))
    )
    cors_allow_origins: list[str] | None = field(default=None)
    user_agent: str = field(
        default_factory=lambda: os.getenv(
            "USER_AGENT",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
        )
    )
    cookie: str = field(
        default_factory=lambda: os.getenv("COOKIE", "")
    )
    extra_headers: dict[str, str] = field(default_factory=dict)

    public_base_url: str = field(
        default_factory=lambda: os.getenv("PUBLIC_BASE_URL", "")
    )
    cover_cache_path: str = field(
        default_factory=lambda: os.getenv("COVER_CACHE_PATH", "cover_cache")
    )
    cover_cache_ttl_seconds: int = field(
        default_factory=lambda: int(os.getenv("COVER_CACHE_TTL_SECONDS", "86400"))
    )
