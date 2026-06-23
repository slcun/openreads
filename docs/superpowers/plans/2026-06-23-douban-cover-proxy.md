# Douban Cover Proxy Implementation Plan

**Goal:** Proxy and disk-cache Douban cover images by ISBN.

**Architecture:** Keep ISBN metadata in `SqliteCache`; add a filesystem-backed
cover cache and a restricted downloader in the proxy service. `BookResponse`
emits a stable proxy URL using configured `PUBLIC_BASE_URL`.

---

### Task 1: Configuration and cache component

Files: modify `tools/douban-isbn-proxy/douban_isbn_proxy/config.py`; create
`tools/douban-isbn-proxy/douban_isbn_proxy/cover_cache.py`; test in
`tools/douban-isbn-proxy/tests/test_cover_cache.py`.

1. Add `PUBLIC_BASE_URL`, `COVER_CACHE_PATH`, and `COVER_CACHE_TTL_SECONDS`.
2. Write failing tests for atomic write, type-derived extension, ETag, expiry,
   and cache miss.
3. Implement `CoverCache.get(isbn)` and `CoverCache.put(isbn, content_type,
   bytes)` with temp-file rename.
4. Run `pytest tests/test_cover_cache.py`.

### Task 2: Restricted image fetch

Files: modify `tools/douban-isbn-proxy/douban_isbn_proxy/app.py`; test in
`tools/douban-isbn-proxy/tests/test_app.py`.

1. Write failing tests showing a Doubanio HTTPS image is requested with the
   fixed book Referer, and a non-Douban host/redirect/non-image response is
   rejected.
2. Add a cover fetch method that accepts only parsed HTTPS `*.doubanio.com`
   URLs, uses `follow_redirects=False`, checks `image/*`, and enforces the
   configured timeout.
3. Run `pytest tests/test_app.py`.

### Task 3: Public API

Files: modify `tools/douban-isbn-proxy/douban_isbn_proxy/app.py`; modify
`tools/douban-isbn-proxy/tests/test_app.py`.

1. Write failing tests for proxy `cover_url`, `/v1/covers/{isbn}` cache hit,
   cache miss fetch/write, invalid ISBN (`422`), no cover (`404`), and upstream
   failure (`502`).
2. Make `BookResponse.from_metadata` receive the configured public base URL
   and emit `/v1/covers/{isbn}` only when a cover exists.
3. Add the named `GET /v1/covers/{isbn}` route with image response,
   `Cache-Control`, and ETag.
4. Run `pytest tests/test_app.py`.

### Task 4: Deployment documentation and verification

Files: modify `tools/douban-isbn-proxy/README.md`; modify
`tools/douban-isbn-proxy/docker-compose.yml` only if the cover-cache path
needs an additional volume mapping.

1. Document new environment variables, endpoint behavior, cache persistence,
   and reverse-proxy public URL requirement.
2. Run `pytest` from `tools/douban-isbn-proxy` and the container contract test.
3. Start the container and verify one ISBN response returns a proxy cover URL
   and the second cover request is served from disk cache.
