# Douban ISBN Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Add a self-hosted Python/FastAPI service that resolves one ISBN to Douban Book metadata, plus an Openreads preset that installs it as the highest-priority custom ISBN source.

**Architecture:** The proxy lives in \`tools/douban-isbn-proxy\` as an independently testable Python package. Its HTTP route delegates ISBN validation, SQLite TTL caching, serialized low-frequency upstream requests, and semantic HTML parsing. The Flutter app stores only the HTTPS base URL as a normal \`IsbnDataSource\`; existing custom lookup and Open Library fallback remain unchanged.

**Tech Stack:** Python 3.12, FastAPI, httpx, Beautiful Soup, SQLite, pytest, Docker Compose, Flutter, flutter_test, hydrated_bloc.

---

## File structure

- Create: \`tools/douban-isbn-proxy/pyproject.toml\` — package dependencies and pytest setup.
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/{config,isbn,models,cache,douban,app,__main__}.py\` — configuration, pure ISBN logic, cache, source parsing, and API.
- Create: \`tools/douban-isbn-proxy/tests/\` and \`tests/fixtures/\` — no-network parser, cache, service, and HTTP-contract tests.
- Create: \`tools/douban-isbn-proxy/{Dockerfile,docker-compose.yml,.env.example,README.md}\` — local service deployment.
- Create: \`lib/resources/douban_isbn_source_preset.dart\` — HTTPS URL validation and standard source mapping.
- Modify: \`lib/logic/cubit/isbn_data_sources_cubit.dart\` — idempotent first-position upsert.
- Modify: \`lib/ui/settings_screen/isbn_data_sources_screen.dart\` — configure-proxy dialog.
- Modify: \`assets/translations/en-US.json\`, \`assets/translations/zh-CN.json\`, \`lib/generated/locale_keys.g.dart\`.
- Create/modify: focused Python and Flutter tests listed in the tasks.

### Task 1: Create the Python foundation and ISBN equivalence logic

**Files:**
- Create: \`tools/douban-isbn-proxy/pyproject.toml\`
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/__init__.py\`
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/isbn.py\`
- Test: \`tools/douban-isbn-proxy/tests/test_isbn.py\`

- [ ] **Step 1: Write the failing ISBN tests.**

~~~python
from douban_isbn_proxy.isbn import normalize_isbn, same_edition

def test_normalize_isbn_removes_formatting_and_uppercases_x():
    assert normalize_isbn(" 0-306-40615-x ") == "030640615X"
    assert normalize_isbn("978-0-306-40615-7") == "9780306406157"

def test_same_edition_accepts_equivalent_isbn_10_and_13():
    assert same_edition("0306406152", "9780306406157") is True

def test_normalize_isbn_rejects_a_bad_checksum():
    assert normalize_isbn("9780306406158") is None
~~~

- [ ] **Step 2: Run the test and confirm the expected red state.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_isbn.py -q\`  
Expected: FAIL with \`ModuleNotFoundError: No module named 'douban_isbn_proxy'\`.

- [ ] **Step 3: Implement the package and minimal validated normalization.**

~~~toml
[project]
name = "douban-isbn-proxy"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
  "fastapi>=0.115,<1",
  "httpx>=0.28,<1",
  "beautifulsoup4>=4.12,<5",
  "uvicorn[standard]>=0.34,<1",
]

[dependency-groups]
test = ["pytest>=8.3,<9"]

[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]
~~~

~~~python
import re

def normalize_isbn(value: str) -> str | None:
    compact = re.sub(r"[^0-9Xx]", "", value).upper()
    if len(compact) == 10 and _valid_isbn10(compact):
        return compact
    if len(compact) == 13 and compact.isdigit() and _valid_isbn13(compact):
        return compact
    return None

def same_edition(left: str, right: str) -> bool:
    left_normalized = normalize_isbn(left)
    right_normalized = normalize_isbn(right)
    return (
        left_normalized is not None
        and right_normalized is not None
        and _to_isbn13(left_normalized) == _to_isbn13(right_normalized)
    )
~~~

Implement \`_valid_isbn10\`, \`_valid_isbn13\`, and \`_to_isbn13\` using standard check digits; conversion may only occur after validation.

- [ ] **Step 4: Verify green.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_isbn.py -q\`  
Expected: PASS with three tests.

- [ ] **Step 5: Commit the foundation.**

~~~bash
git add tools/douban-isbn-proxy/pyproject.toml tools/douban-isbn-proxy/douban_isbn_proxy tools/douban-isbn-proxy/tests/test_isbn.py
git commit -m "feat: add Douban ISBN proxy foundation"
~~~

### Task 2: Implement metadata parsing and TTL cache without live requests

**Files:**
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/models.py\`
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/cache.py\`
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/douban.py\`
- Create: \`tools/douban-isbn-proxy/tests/fixtures/{search,detail_matching,detail_mismatched}.html\`
- Test: \`tools/douban-isbn-proxy/tests/{test_cache,test_douban_parser}.py\`

- [ ] **Step 1: Add failing cache and parser tests using checked-in fixtures.**

~~~python
def test_cache_returns_unexpired_not_found_and_expires_it(tmp_path):
    cache = SqliteCache(tmp_path / "cache.db", ttl_seconds=60, clock=lambda: 100)
    cache.put_not_found("9780306406157")
    assert cache.get("9780306406157") == CacheEntry.not_found()
    expired = SqliteCache(tmp_path / "cache.db", ttl_seconds=60, clock=lambda: 161)
    assert expired.get("9780306406157") is None

def test_detail_parser_returns_only_a_matching_isbn():
    result = parse_detail_html(load_fixture("detail_matching.html"), "9780306406157")
    assert result.title == "Fixture Book"
    assert result.source_id == "1234567"
    assert result.authors == ["Ada Author", "Bob Writer"]

def test_detail_parser_rejects_a_different_edition():
    assert parse_detail_html(load_fixture("detail_mismatched.html"), "9780306406157") is None
~~~

Fixtures must contain only minimal, fabricated HTML: one search page with subject links; one matching detail page; one mismatched ISBN page. Never put live response bodies into the repository.

- [ ] **Step 2: Verify red.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_cache.py tools/douban-isbn-proxy/tests/test_douban_parser.py -q\`  
Expected: FAIL during collection because cache and parser symbols are absent.

- [ ] **Step 3: Add the cache, response model, and semantic parser.**

~~~python
@dataclass(frozen=True)
class BookMetadata:
    title: str
    isbn: str
    source_id: str
    authors: list[str] = field(default_factory=list)
    cover_url: str | None = None
    publisher: str | None = None
    publication_year: int | None = None
    page_count: int | None = None
    description: str | None = None
    rating: float | None = None
    rating_count: int | None = None

class SqliteCache:
    def get(self, isbn: str) -> CacheEntry | None: ...
    def put_success(self, metadata: BookMetadata) -> None: ...
    def put_not_found(self, isbn: str) -> None: ...
~~~

The SQLite table has \`isbn\` as the primary key plus \`kind\` (\`success\` or \`not_found\`), \`payload_json\`, and \`expires_at\`. Delete an expired entry before returning \`None\`. Store normalized JSON only, never raw HTML.

Use Beautiful Soup to collect candidate \`/subject/<digits>/\` URLs and parse the detail-page title, ISBN, author, cover, publisher, publication year, page count, description, rating, and rating count using field labels in the information block. Return a result only if a parsed ISBN is equivalent to the request. Convert relative cover links to HTTPS.

- [ ] **Step 4: Verify green.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_cache.py tools/douban-isbn-proxy/tests/test_douban_parser.py -q\`  
Expected: PASS with no network access.

- [ ] **Step 5: Commit.**

~~~bash
git add tools/douban-isbn-proxy/douban_isbn_proxy/models.py tools/douban-isbn-proxy/douban_isbn_proxy/cache.py tools/douban-isbn-proxy/douban_isbn_proxy/douban.py tools/douban-isbn-proxy/tests
git commit -m "feat: parse and cache Douban ISBN metadata"
~~~

### Task 3: Add paced upstream lookup and FastAPI responses

**Files:**
- Create: \`tools/douban-isbn-proxy/douban_isbn_proxy/{config,app,__main__}.py\`
- Test: \`tools/douban-isbn-proxy/tests/test_app.py\`

- [ ] **Step 1: Write failing HTTP-contract tests with fake transport and clock.**

~~~python
def test_route_returns_metadata_then_uses_cache(client, upstream):
    upstream.queue_search_and_detail("9780306406157")
    first = client.get("/v1/books/isbn/9780306406157")
    second = client.get("/v1/books/isbn/9780306406157")
    assert first.status_code == second.status_code == 200
    assert second.json()["source_id"] == "1234567"
    assert upstream.request_count == 2

def test_route_returns_404_for_confirmed_absence(client, upstream):
    upstream.queue_search_without_candidates()
    assert client.get("/v1/books/isbn/9780306406157").status_code == 404

def test_route_returns_429_and_retry_after_when_paced(client, upstream):
    upstream.queue_search_and_detail("9780306406157")
    assert client.get("/v1/books/isbn/9780306406157").status_code == 200
    response = client.get("/v1/books/isbn/9781492056355")
    assert response.status_code == 429
    assert response.headers["retry-after"] == "2"
~~~

Also cover invalid ISBN \`422\`, upstream connection/timeout/parser failures \`502\`, unavailable dependencies \`503\`, and log output that contains neither \`<html\` nor a full search URL.

- [ ] **Step 2: Verify red.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_app.py -q\`  
Expected: FAIL with missing \`create_app\`.

- [ ] **Step 3: Implement the route and coordinator.**

~~~python
def create_app(settings: Settings, lookup: DoubanLookup) -> FastAPI:
    app = FastAPI(title="Douban ISBN Proxy")

    @app.get("/v1/books/isbn/{isbn}", response_model=BookResponse)
    async def get_book(isbn: str) -> BookResponse:
        result = await lookup.lookup(isbn)
        if result is None:
            raise HTTPException(status_code=404, detail="book not found")
        return BookResponse.from_metadata(result)

    @app.get("/healthz", status_code=204)
    async def healthz() -> Response:
        lookup.assert_ready()
        return Response(status_code=204)

    return app
~~~

\`DoubanLookup.lookup\` reads cache first. If uncached, it uses a single process-wide \`asyncio.Lock\` and a monotonic timestamp to enforce \`minimum_request_interval_seconds\` before every upstream page request. It fetches the ISBN search page and then candidates one by one; the first matching detail page wins. Cache success and confirmed no-result values. Do not retry requests, configure cookies, use browser automation, or bypass any access restriction. Convert \`httpx\` and parser failures to a typed upstream error, which the route maps to \`502\`. Map only deliberate local pacing to \`429\`.

- [ ] **Step 4: Verify green.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests -q\`  
Expected: PASS, including status, cache, pacing, and sanitised-log tests.

- [ ] **Step 5: Commit.**

~~~bash
git add tools/douban-isbn-proxy/douban_isbn_proxy/config.py tools/douban-isbn-proxy/douban_isbn_proxy/app.py tools/douban-isbn-proxy/douban_isbn_proxy/__main__.py tools/douban-isbn-proxy/tests/test_app.py
git commit -m "feat: expose paced Douban ISBN lookup API"
~~~

### Task 4: Package and document Docker and direct-Python operation

**Files:**
- Create: \`tools/douban-isbn-proxy/{Dockerfile,docker-compose.yml,.env.example,README.md}\`
- Test: \`tools/douban-isbn-proxy/tests/test_container_contract.py\`

- [ ] **Step 1: Write a failing container health test.**

~~~python
def test_container_exposes_health_route(tmp_path):
    # Build locally, bind only 127.0.0.1:18080, and mount tmp_path at /data.
    response = requests.get("http://127.0.0.1:18080/healthz", timeout=5)
    assert response.status_code == 204
~~~

The helper must always stop and remove the container in \`finally\`.

- [ ] **Step 2: Verify red.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_container_contract.py -q\`  
Expected: FAIL because \`Dockerfile\` is absent.

- [ ] **Step 3: Add repeatable deployment artefacts.**

~~~dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY douban_isbn_proxy ./douban_isbn_proxy
RUN pip install --no-cache-dir .
ENV DOUBAN_PROXY_CACHE_PATH=/data/cache.sqlite3
EXPOSE 8080
CMD ["python", "-m", "douban_isbn_proxy"]
~~~

~~~yaml
services:
  douban-isbn-proxy:
    build: .
    env_file: .env
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - douban-isbn-cache:/data
volumes:
  douban-isbn-cache:
~~~

Document \`docker compose up -d --build\`, \`python -m douban_isbn_proxy\`, cache backup, and low-frequency single-ISBN scope. The current app intentionally accepts only HTTPS custom-source URLs, so document a user-managed HTTPS reverse proxy for phone-accessible deployment. Do not change Flutter to trust arbitrary HTTP endpoints.

- [ ] **Step 4: Verify the image and direct startup.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests/test_container_contract.py -q\`  
Expected: PASS with \`/healthz\` returning \`204\`.

Run: \`cd tools/douban-isbn-proxy; python -m douban_isbn_proxy\`  
Expected: Uvicorn starts; \`curl -i http://127.0.0.1:8080/healthz\` returns \`204\`.

- [ ] **Step 5: Commit.**

~~~bash
git add tools/douban-isbn-proxy/Dockerfile tools/douban-isbn-proxy/docker-compose.yml tools/douban-isbn-proxy/.env.example tools/douban-isbn-proxy/README.md tools/douban-isbn-proxy/tests/test_container_contract.py
git commit -m "docs: add Douban ISBN proxy deployment"
~~~

### Task 5: Add the Openreads preset without altering lookup fallback

**Files:**
- Create: \`lib/resources/douban_isbn_source_preset.dart\`
- Modify: \`lib/logic/cubit/isbn_data_sources_cubit.dart\`
- Modify: \`lib/ui/settings_screen/isbn_data_sources_screen.dart\`
- Modify: \`assets/translations/en-US.json\`, \`assets/translations/zh-CN.json\`, \`lib/generated/locale_keys.g.dart\`
- Test: \`test/resources/douban_isbn_source_preset_test.dart\`
- Modify: \`test/ui/settings_screen/isbn_data_sources_screen_test.dart\`

- [ ] **Step 1: Write failing source-mapping and widget tests.**

~~~dart
test("creates a top-priority Douban source from an HTTPS base URL", () {
  final source = DoubanIsbnSourcePreset.create("https://books.example/proxy/");
  expect(source.id, "douban-isbn-proxy");
  expect(source.urlTemplate, "https://books.example/proxy/v1/books/isbn/{isbn}");
  expect(source.titleJsonPath, r"$.title");
  expect(source.authorJsonPath, r"$.authors[*]");
  expect(source.sourceIdJsonPath, r"$.source_id");
});

test("rejects a non-HTTPS base URL", () {
  expect(
    () => DoubanIsbnSourcePreset.create("http://192.168.1.2:8080"),
    throwsFormatException,
  );
});
~~~

Add a widget test that taps \`douban-source-add\`, enters an HTTPS host into \`douban-source-base-url\`, confirms it, and verifies the Cubit's first source is the preset without an API key.

- [ ] **Step 2: Verify red.**

Run: \`flutter test test/resources/douban_isbn_source_preset_test.dart test/ui/settings_screen/isbn_data_sources_screen_test.dart\`  
Expected: FAIL at compile time because the preset and dialog controls do not exist.

- [ ] **Step 3: Implement the source factory and dialog.**

~~~dart
class DoubanIsbnSourcePreset {
  static const id = "douban-isbn-proxy";

  static IsbnDataSource create(String baseUrl) {
    final baseUri = _httpsBaseUri(baseUrl);
    return IsbnDataSource(
      id: id,
      name: "Douban ISBN Proxy",
      enabled: true,
      method: IsbnRequestMethod.get,
      urlTemplate: baseUri.resolve("v1/books/isbn/{isbn}").toString(),
      titleJsonPath: r"$.title",
      authorJsonPath: r"$.authors[*]",
      isbnJsonPath: r"$.isbn",
      coverUrlJsonPath: r"$.cover_url",
      publisherJsonPath: r"$.publisher",
      publicationYearJsonPath: r"$.publication_year",
      pageCountJsonPath: r"$.page_count",
      descriptionJsonPath: r"$.description",
      sourceIdJsonPath: r"$.source_id",
    );
  }
}
~~~

Implement \`_httpsBaseUri\` so it trims input, requires an HTTPS scheme and host, and appends one trailing slash. Add \`IsbnDataSourcesCubit.upsertFirst\` that removes matching IDs, then emits \`[source, ...remaining]\`. The dialog uses a validated \`TextFormField\`, Cancel, and Add; retain manual source editing unchanged. Add bilingual strings and regenerate \`LocaleKeys\` using the existing repository localization workflow.

- [ ] **Step 4: Verify green.**

Run: \`flutter test test/resources/douban_isbn_source_preset_test.dart test/ui/settings_screen/isbn_data_sources_screen_test.dart\`  
Expected: PASS.

Run: \`flutter analyze\`  
Expected: \`No issues found!\`.

- [ ] **Step 5: Commit.**

~~~bash
git add lib/resources/douban_isbn_source_preset.dart lib/logic/cubit/isbn_data_sources_cubit.dart lib/ui/settings_screen/isbn_data_sources_screen.dart assets/translations/en-US.json assets/translations/zh-CN.json lib/generated/locale_keys.g.dart test/resources/douban_isbn_source_preset_test.dart test/ui/settings_screen/isbn_data_sources_screen_test.dart
git commit -m "feat: add Douban ISBN proxy source preset"
~~~

### Task 6: Verify integration and record constrained operational evidence

**Files:**
- Modify: \`tools/douban-isbn-proxy/README.md\` only if a verification note is required.
- Modify: \`docs/superpowers/specs/2026-06-23-douban-isbn-proxy-design.md\` only if verification exposes a real specification defect.

- [ ] **Step 1: Run the complete proxy suite.**

Run: \`python -m pytest tools/douban-isbn-proxy/tests -q\`  
Expected: PASS with ISBN, parser, cache, pace, HTTP, log, and container checks.

- [ ] **Step 2: Run all relevant Flutter tests.**

Run: \`flutter test test/model test/logic/cubit test/resources test/ui/settings_screen test/ui/search_ol_screen\`  
Expected: PASS, including existing custom-source mapping and Open Library fallback coverage.

- [ ] **Step 3: Run analysis and production build.**

Run: \`flutter analyze\`  
Expected: \`No issues found!\`.

Run: \`flutter build apk\`  
Expected: exits with status \`0\`.

- [ ] **Step 4: Execute exactly one live upstream smoke request.**

Run: \`docker compose -f tools/douban-isbn-proxy/docker-compose.yml up -d --build\`  
Expected: the service starts and \`/healthz\` returns \`204\`.

Send one known ISBN to the local proxy. Record only the HTTP status and returned field names; do not save raw HTML or retry after an upstream access failure.

- [ ] **Step 5: Commit only a documentation change caused by verification.**

~~~bash
git add tools/douban-isbn-proxy/README.md docs/superpowers/specs/2026-06-23-douban-isbn-proxy-design.md
git commit -m "docs: record Douban ISBN proxy verification"
~~~
