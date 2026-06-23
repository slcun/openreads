# Douban cover proxy and cache

## Goal

Return proxy-hosted cover URLs from ISBN lookups, so Openreads loads covers
from the user's proxy rather than directly from Douban's restricted image host.

## API and flow

`GET /v1/books/isbn/{isbn}` will return `cover_url` as
`{PUBLIC_BASE_URL}/v1/covers/{normalized-isbn}` when metadata has a cover.
`PUBLIC_BASE_URL` is required to be an absolute public URL; it is not inferred
from request headers.

`GET /v1/covers/{isbn}` normalizes the ISBN, obtains metadata through the
existing lookup/cache path, and returns `404` when there is no cover. On a file
cache hit it returns the stored image. On a miss it downloads only the parsed
Douban image URL, adds `Referer: https://book.douban.com/` and the configured
user agent, then atomically writes and returns the image.

## Safety and cache boundaries

The cover endpoint accepts an ISBN, never an upstream URL. The downloader only
accepts HTTPS URLs whose hostname is `doubanio.com` or a subdomain. Redirects
are disabled. Images are stored under a configured cover-cache directory using
the normalized ISBN plus an extension derived from the validated content type.
SQLite continues to cache metadata only; it does not store image blobs.

Success responses use a long client cache header and ETag based on the cached
file. Failed upstream fetches return `502` and are not cached as images.

## Verification

Tests prove response URL generation, cache hit without upstream traffic,
referer/header use on fetch, host/type rejection, and invalid/missing ISBN
responses. The full Python suite and container contract remain green.
