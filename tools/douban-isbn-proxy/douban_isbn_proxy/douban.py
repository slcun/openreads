import json
import re

from bs4 import BeautifulSoup, Tag

from douban_isbn_proxy.isbn import normalize_isbn, same_edition
from douban_isbn_proxy.models import BookMetadata


def parse_search_html(html: str) -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    links: list[str] = []
    for a in soup.select('a[href*="/subject/"]'):
        _append_subject_url(links, str(a.get("href", "")))

    for script in soup.find_all("script"):
        text = script.string or script.get_text()
        marker = "window.__DATA__ ="
        if marker not in text:
            continue
        try:
            data, _ = json.JSONDecoder().raw_decode(text.split(marker, 1)[1].lstrip())
        except json.JSONDecodeError:
            continue
        for url in _subject_urls_in_data(data):
            _append_subject_url(links, url)

    return links


def _append_subject_url(links: list[str], url: str) -> None:
    if not re.search(r"/subject/\d+/", url):
        return
    full = url if url.startswith("http") else "https://book.douban.com" + url
    if full not in links:
        links.append(full)


def _subject_urls_in_data(value: object) -> list[str]:
    if isinstance(value, dict):
        urls = [item for item in value.values() if isinstance(item, str)]
        for item in value.values():
            urls.extend(_subject_urls_in_data(item))
        return urls
    if isinstance(value, list):
        return [url for item in value for url in _subject_urls_in_data(item)]
    return []


def parse_detail_html(html: str, isbn: str) -> BookMetadata | None:
    soup = BeautifulSoup(html, "html.parser")

    wrapper = soup.find(id="wrapper")
    if not isinstance(wrapper, Tag):
        return None

    title_el = wrapper.find("h1")
    title = title_el.get_text(strip=True) if isinstance(title_el, Tag) else ""

    info_el = wrapper.find(id="info")
    fields = _parse_info_block(info_el if isinstance(info_el, Tag) else None)

    parsed_isbn = fields.get("isbn", "")
    if not title or not parsed_isbn or not same_edition(parsed_isbn, isbn):
        return None

    source_id = _extract_source_id(wrapper)

    authors = _parse_authors(fields.get("author", ""))

    cover_url = _parse_cover_url(wrapper)

    publisher = fields.get("publisher")
    pub_year = _parse_int(fields.get("publication_year"))
    page_count = _parse_int(fields.get("page_count"))

    description = _parse_description(wrapper)

    rating, rating_count = _parse_rating(wrapper)

    normalized = normalize_isbn(parsed_isbn)
    if normalized is None:
        return None

    return BookMetadata(
        title=title,
        isbn=normalized,
        source_id=source_id,
        authors=authors,
        cover_url=cover_url,
        publisher=publisher,
        publication_year=pub_year,
        page_count=page_count,
        description=description,
        rating=rating,
        rating_count=rating_count,
    )


_LABEL_MAP: dict[str, str] = {
    "作者": "author",
    "出版社": "publisher",
    "出版年": "publication_year",
    "页数": "page_count",
    "isbn": "isbn",
    "定价": "price",
}


def _parse_info_block(info: Tag | None) -> dict[str, str]:
    if info is None:
        return {}

    fields: dict[str, str] = {}
    labels = info.select("span.pl")
    for label in labels:
        key = label.get_text(strip=True).rstrip(":：").strip()
        mapped = _LABEL_MAP.get(key, key.lower())
        values: list[str] = []
        for sibling in label.next_siblings:
            if isinstance(sibling, Tag) and (
                sibling.name == "br" or "pl" in (sibling.get("class") or [])
            ):
                break
            text = (
                sibling.get_text(" ", strip=True)
                if isinstance(sibling, Tag)
                else str(sibling).strip()
            )
            if text:
                values.append(text)
        fields[mapped] = " ".join(values)

    if fields:
        return fields

    for line in info.get_text("\n", strip=True).split("\n"):
        line = line.strip()
        for sep in (":", "："):
            if sep in line:
                key, _, value = line.partition(sep)
                key = key.strip()
                mapped = _LABEL_MAP.get(key, key.lower())
                fields[mapped] = value.strip()
                break
    return fields


def _parse_authors(raw: str) -> list[str]:
    return [a.strip() for a in re.split(r"[/／、,，·]", raw) if a.strip()]


def _extract_source_id(wrapper: Tag) -> str:
    for a in wrapper.select('a[href*="/subject/"]'):
        m = re.search(r"/subject/(\d+)/", a.get("href", ""))
        if m:
            return m.group(1)
    return ""


def _parse_cover_url(wrapper: Tag) -> str | None:
    mainpic = wrapper.find(id="mainpic")
    if not isinstance(mainpic, Tag):
        return None
    img = mainpic.find("img")
    if not isinstance(img, Tag):
        return None
    src = img.get("src", "")
    if not src:
        return None
    return src if src.startswith("http") else "https:" + src


def _parse_description(wrapper: Tag) -> str | None:
    intro = wrapper.find("div", class_="intro")
    if not isinstance(intro, Tag):
        return None
    text = intro.get_text(" ", strip=True)
    return text or None


def _parse_rating(wrapper: Tag) -> tuple[float | None, int | None]:
    rating_el = wrapper.select_one(".rating_self strong.ll")
    rating: float | None = None
    if isinstance(rating_el, Tag):
        try:
            rating = float(rating_el.get_text(strip=True))
        except ValueError:
            pass

    rating_people = wrapper.find("span", class_="rating_people")
    rating_count: int | None = None
    if isinstance(rating_people, Tag):
        num_el = rating_people.find("span")
        if isinstance(num_el, Tag) and num_el.get_text(strip=True).isdigit():
            rating_count = int(num_el.get_text(strip=True))

    return rating, rating_count


def _parse_int(value: str | None) -> int | None:
    if value is None:
        return None
    digits = re.sub(r"[^\d]", "", value)
    return int(digits) if digits else None
