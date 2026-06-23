from douban_isbn_proxy.app import DoubanLookup, create_app
from douban_isbn_proxy.cache import SqliteCache
from douban_isbn_proxy.config import Settings
import httpx
import uvicorn


def main():
    settings = Settings()
    cache = SqliteCache(settings.cache_path, ttl_seconds=settings.cache_ttl_seconds)
    client = httpx.AsyncClient(timeout=settings.request_timeout_seconds)
    lookup = DoubanLookup(
        cache=cache,
        client=client,
        minimum_request_interval_seconds=settings.minimum_request_interval_seconds,
        request_timeout_seconds=settings.request_timeout_seconds,
        user_agent=settings.user_agent,
    )
    app = create_app(settings=settings, lookup=lookup)
    uvicorn.run(app, host=settings.bind_host, port=settings.bind_port)


if __name__ == "__main__":
    main()
