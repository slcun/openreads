# Custom ISBN Data Sources Design

## Goal

Allow users to configure multiple custom book-metadata endpoints for ISBN lookup. Sources run in user-defined priority order. Open Library remains the final fallback.

## Source Configuration

The Settings screen will provide an ISBN data-source list. Users can add, edit, enable, disable, delete, and reorder sources. A source contains:

- Display name and enabled state.
- `GET` or `POST` request method.
- URL template, supporting `{isbn}` and `{apiKey}` anywhere in the URL, including query parameters.
- Optional headers; POST body mode (`application/json` or form data) and a template body, also supporting placeholders.
- A separately entered API key, displayed masked in the UI.
- A request timeout.
- JSONPath mappings for title, authors, ISBN, cover URL, description, publisher, publication year, page count, and optional source ID.

The configuration permits JSONPath extraction only. It does not evaluate scripts, regular expressions, cookies, or arbitrary authentication flows.

## Lookup Behaviour

When the user scans or enters an ISBN, the app normalizes it and calls enabled sources serially in their saved order. A response is successful only when it can be parsed as JSON and its mapped title is non-empty. The first successful response becomes the selected result; later sources are not called and data from separate sources is never merged.

For each source, timeouts, transport failures, non-success HTTP statuses, invalid JSON, unsupported response shape, invalid JSONPath, or an empty title are treated as a failed attempt. The lookup then continues with the next configured source. If no custom source succeeds, the existing Open Library ISBN lookup executes unchanged.

Imported books retain the provider name and optional provider-specific source ID. The existing `olid` field remains exclusive to Open Library identifiers.

## User Experience

The source list shows each source's name, method, endpoint host, enabled state, and order. An edit screen provides field mapping inputs and a Test action. Test accepts a sample ISBN and reports either the mapped preview fields or a sanitised failure; URL query keys and API-key values are never exposed in logs or error messages.

## Validation and Testing

Validate that a URL is HTTPS, templates are syntactically valid, and at least a title mapping is present. Test source-template expansion, GET/POST construction, JSONPath mappings, first-success short-circuiting, error-to-fallback behaviour, persistence, and masking of sensitive configuration values. Existing Open Library lookup tests must continue to pass.
