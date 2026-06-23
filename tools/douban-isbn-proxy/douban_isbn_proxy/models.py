from dataclasses import dataclass, field


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
