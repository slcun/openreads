# Douban ISBN Proxy

A lightweight HTTP proxy that looks up book metadata by ISBN from Douban (book.douban.com). Designed for **low-frequency, single-ISBN lookups** — not for bulk scraping.

## Quick Start — Docker Compose

```bash
cp .env.example .env
docker compose up -d --build
curl -i http://127.0.0.1:8080/healthz
# Expected: HTTP/1.1 204 No Content
```

## Quick Start — Direct Python

```bash
pip install .
python -m douban_isbn_proxy
curl -i http://127.0.0.1:8080/healthz
# Expected: HTTP/1.1 204 No Content
```

The default bind address is `0.0.0.0:8080`. Override with environment variables (see below).

## API

### `GET /healthz`

Returns `204 No Content` when the service is ready. Use for health checks.

### `GET /v1/books/isbn/{isbn}`

Returns book metadata as JSON, or `404` if not found, `429` if rate-limited, `502` on upstream error.

```json
{
  "title": "百年孤独",
  "authors": ["加西亚·马尔克斯"],
  "isbn": "9787544253994",
  "cover_url": "https://img2.doubanio.com/...",
  "publisher": "南海出版公司",
  "publication_year": 2011,
  "page_count": 360,
  "description": "...",
  "source_id": "https://book.douban.com/subject/...",
  "rating": 9.2,
  "rating_count": 400000
}
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `BIND_HOST` | `0.0.0.0` | Bind address |
| `BIND_PORT` | `8080` | Bind port |
| `DOUBAN_PROXY_CACHE_PATH` | `cache.db` | SQLite cache file path |
| `CACHE_TTL_SECONDS` | `86400` | Cache TTL (seconds, 24 h) |
| `MINIMUM_REQUEST_INTERVAL_SECONDS` | `2.0` | Minimum interval between upstream requests |
| `REQUEST_TIMEOUT_SECONDS` | `30.0` | HTTP request timeout |

`DOUBAN_PROXY_CACHE_PATH` takes precedence over the legacy `CACHE_PATH` variable.

## Cache Management

The cache is a single SQLite file. To back it up:

```bash
# Docker
docker cp <container>:/data/cache.sqlite3 ./cache-backup.sqlite3

# Direct
cp cache.db cache-backup.db
```

To clear the cache:

```bash
# Docker
docker compose down -v   # removes the named volume

# Direct
rm cache.db
```

## HTTPS Reverse Proxy

The app binds to `0.0.0.0:8080` by default and serves plain HTTP. If you need to access the proxy from a phone (e.g., to configure Openreads with a custom source URL), you must place an HTTPS reverse proxy in front — for example, Caddy or Nginx with a Let's Encrypt certificate.

The Flutter app is intentionally designed to accept only HTTPS custom-source URLs and will **not** trust arbitrary HTTP endpoints. This is a security measure and will not be changed.

Example Caddyfile:

```
your-domain.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

## Scope and Limitations

- **Low-frequency, single-ISBN lookups only.** The proxy enforces a minimum 2-second interval between requests to Douban. Bulk lookups will trigger rate limiting (`429`).
- **No credentials or API keys.** The proxy scrapes public Douban pages. No authentication is required or supported.
- **No CAPTCHA bypass.** If Douban presents a CAPTCHA, the proxy will return a `502` upstream error.
- **No search by title or author.** Only ISBN-based lookup is supported.
- **Cache is local.** Each instance has its own SQLite cache. There is no distributed cache or synchronization.
