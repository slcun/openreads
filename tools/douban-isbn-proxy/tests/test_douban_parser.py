from pathlib import Path

import pytest

from douban_isbn_proxy.douban import (
    parse_detail_html,
    parse_mobile_search_html,
    parse_search_html,
)


def load_fixture(name: str) -> str:
    return (Path(__file__).parent / "fixtures" / name).read_text(encoding="utf-8")


def test_search_parser_extracts_subject_links():
    html = load_fixture("search.html")
    links = parse_search_html(html)
    assert links == ["https://book.douban.com/subject/1234567/"]


def test_search_parser_extracts_subject_links_from_embedded_data():
    html = '''<script>
window.__DATA__ = {"items": [
  {"url": "https://book.douban.com/subject/7654321/"}
]};
</script>'''

    links = parse_search_html(html)

    assert links == ["https://book.douban.com/subject/7654321/"]


def test_mobile_search_parser_normalizes_book_subject_relative_urls():
    html = '<a href="/book/subject/38383937/">Book</a>'

    links = parse_mobile_search_html(html)

    assert links == ["https://book.douban.com/subject/38383937/"]


def test_detail_parser_returns_only_a_matching_isbn():
    result = parse_detail_html(load_fixture("detail_matching.html"), "9780306406157")
    assert result is not None
    assert result.title == "Fixture Book"
    assert result.source_id == "1234567"
    assert result.authors == ["Ada Author", "Bob Writer"]
    assert result.publisher == "Test Press"
    assert result.publication_year == 2024
    assert result.page_count == 300
    assert result.cover_url == "https://img1.doubanio.com/view/subject/l/public/s1234567.jpg"
    assert result.description == "This is a test book description."
    assert result.rating == 4.5
    assert result.rating_count == 100


def test_detail_parser_rejects_a_different_edition():
    assert parse_detail_html(load_fixture("detail_mismatched.html"), "9780306406157") is None


def test_detail_parser_handles_missing_fields():
    html = """<html><body><div id="wrapper">
<h1><span>Minimal Book</span></h1>
<div id="info">ISBN: 9780306406157</div>
</div></body></html>"""
    result = parse_detail_html(html, "9780306406157")
    assert result is not None
    assert result.title == "Minimal Book"
    assert result.authors == []
    assert result.publisher is None
    assert result.publication_year is None
    assert result.page_count is None
    assert result.cover_url is None
    assert result.description is None
    assert result.rating is None
    assert result.rating_count is None


def test_detail_parser_reads_values_after_douban_label_nodes():
    html = '''<html><body><div id="wrapper">
<h1>Label nodes</h1>
<div id="info">
  <span class="pl">作者:</span> <a>Ada Author</a><br/>
  <span class="pl">出版社:</span> Test Press<br/>
  <span class="pl">ISBN:</span> 9780306406157
</div>
</div></body></html>'''

    result = parse_detail_html(html, "9780306406157")

    assert result is not None
    assert result.authors == ["Ada Author"]
    assert result.publisher == "Test Press"


def test_detail_parser_ignores_non_numeric_rating():
    html = '''<html><body><div id="wrapper">
<h1>Unrated</h1>
<div id="info">ISBN: 9780306406157</div>
<div class="rating_self"><strong class="ll">暂无评分</strong></div>
</div></body></html>'''

    result = parse_detail_html(html, "9780306406157")

    assert result is not None
    assert result.rating is None
