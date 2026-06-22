# Douban ISBN Proxy Design

## Goal

Provide a self-hosted, low-frequency metadata adapter for a single ISBN lookup
against Douban Book. Openreads will use the adapter through its existing custom
ISBN JSON data-source mechanism, while retaining Open Library as the fallback.

The adapter is for a user's own Docker host, NAS, or local machine. It is not a
public shared API and does not support bulk collection.

## Scope and boundaries

The new service lives at `tools/douban-isbn-proxy/` and is implemented with
Python and FastAPI. It supports Docker Compose and a direct Python module
startup path.

It accepts one ISBN per request. It does not accept or persist Douban accounts,
cookies, CAPTCHA-bypass configuration, proxy pools, or batch-job requests.
It does not retain raw Douban HTML.

The Flutter app retains its current request and fallback behaviour. A settings
preset will create a compatible custom ISBN source after the user supplies the
adapter base URL, rather than exposing endpoint and JSONPath details.

## HTTP contract

`GET /v1/books/isbn/{isbn}` returns JSON containing:

```json
{
  "title": "string",
  "authors": ["string"],
  "isbn": "978...",
  "cover_url": "https://...",
  "publisher": "string",
  "publication_year": 2026,
  "page_count": 320,
  "description": "string",
  "source_id": "douban-subject-id",
  "rating": 8.4,
  "rating_count": 12345
}
```

`title`, `authors`, `cover_url`, `publisher`, `publication_year`, `page_count`,
`description`, `rating`, and `rating_count` are optional when unavailable from
the source. A successful response requires a non-empty `title` and an ISBN that
matches the request after ISBN-10/ISBN-13 normalization.

Status codes have the following semantics:

- `200`: a matching book was returned.
- `404`: no matching Douban book was found; the app falls back to Open Library.
- `429`: the adapter is deliberately rate-limiting the caller; it includes
  `Retry-After` and the app falls back.
- `502`: Douban could not be read or parsed; the app falls back.
- `503`: the adapter is temporarily unavailable; the app falls back.

## Lookup and parsing

1. Validate and normalize the incoming ISBN-10 or ISBN-13.
2. Return a fresh cached success or not-found response when available.
3. Enforce a configurable minimum interval before a Douban request.
4. Request the Douban Book search page for the ISBN and select candidate book
   detail URLs.
5. Request candidate detail pages in order, parsing semantic fields from their
   title, information, cover, description, and rating regions.
6. Return only a candidate whose detail-page ISBN normalizes to the input ISBN.
7. Cache successful and definitive not-found results for a configurable TTL.

Non-core field omissions do not make a lookup fail. HTML structure changes,
unavailable pages, malformed source data, and a candidate ISBN mismatch do make
that candidate fail. No request may attempt to bypass an access restriction.

## Deployment and configuration

The repository supplies:

- `Dockerfile` and `docker-compose.yml` for a persistent service and SQLite
  cache volume.
- Python package metadata and `python -m douban_isbn_proxy` startup.
- A documented environment file controlling bind address, cache directory,
  cache TTL, minimum upstream request interval, request timeout, and optional
  CORS allow-list.

No deployment configuration contains a Douban credential, Cookie, proxy, or
browser automation setting. Logs are structured and sanitised: they retain
status class and a non-sensitive request identifier, but neither raw HTML nor
complete user-supplied URLs.

## Openreads integration

The app creates a top-priority custom source that uses:

- URL: `{baseUrl}/v1/books/isbn/{isbn}`
- Method: `GET`
- Mappings: `$.title`, `$.authors`, `$.isbn`, `$.cover_url`, `$.publisher`,
  `$.publication_year`, `$.page_count`, `$.description`, and `$.source_id`

The current `CustomIsbnLookupService` handles an adapter failure by continuing
to its next enabled source, and then Open Library. `source_id` is provider data;
it must never populate the Open Library-only `olid` field.

## Verification

- Unit tests cover ISBN normalization and parsing HTML fixtures for matching,
  mismatched, and partially populated book pages.
- Service tests cover response contract, cache hits, cached not-found outcomes,
  request pacing, `404`, `429`, `502`, `503`, and log sanitisation.
- Flutter tests cover the preset configuration and current custom-source-to-
  add-book mapping, including Open Library fallback after non-200 adapter
  outcomes.
- Final checks run the Python test suite, service container health check,
  focused Flutter tests, `flutter analyze`, and the existing full Flutter test
  suite.
