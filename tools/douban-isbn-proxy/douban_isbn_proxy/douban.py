import re

from bs4 import BeautifulSoup, Tag

from douban_isbn_proxy.isbn import normalize_isbn, same_edition
from douban_isbn_proxy.models import BookMetadata


def parse_search_html(html: str) -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    links: list[str] = []
    for a in soup.select('a[href*="/subject/"]'):
        href = a.get("href", "")
        if re.search(r"/subject/\d+/", href):
            full = href if href.startswith("http") else "https://book.douban.com" + href
            if full not in links:
                links.append(full)
    return links


def parse_detail_html(html: str, isbn: str) -> BookMetadata | None:
    soup = BeautifulSoup(html, "html.parser")

    wrapper = soup.find(id="wrapper")
    if not isinstance(wrapper, Tag):
        return None

    title_el = wrapper.find("h1")
    title = title_el.get_text(strip=True) if isinstance(title_el, Tag) else ""

    info_el = wrapper.find(id="info")
    info_text = info_el.get_text("\n", strip=True) if isinstance(info_el, Tag) else ""

    fields = _parse_info_block(info_text)

    parsed_isbn = fields.get("isbn", "")
    if not parsed_isbn or not same_edition(parsed_isbn, isbn):
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
    assert normalized is not None

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


def _parse_info_block(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in text.split("\n"):
        line = line.strip()
        if ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            mapped = _LABEL_MAP.get(key, key.lower())
            fields[mapped] = value.strip()
    return fields


def _parse_authors(raw: str) -> list[str]:
    return [a.strip() for a in re.split(r"[/／、,，]", raw) if a.strip()]


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
    rating_el = wrapper.find("strong", class_="ll")
    rating = float(rating_el.get_text(strip=True)) if isinstance(rating_el, Tag) else None

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
