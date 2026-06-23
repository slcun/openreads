import re


def _valid_isbn10(value: str) -> bool:
    if len(value) != 10:
        return False
    if not value[:9].isdigit():
        return False
    if value[9] not in "0123456789X":
        return False
    total = sum((10 - i) * int(value[i]) for i in range(9))
    remainder = total % 11
    expected = (11 - remainder) % 11
    expected_char = "X" if expected == 10 else str(expected)
    return value[9] == expected_char


def _valid_isbn13(value: str) -> bool:
    if len(value) != 13 or not value.isdigit():
        return False
    total = sum(int(value[i]) * (1 if i % 2 == 0 else 3) for i in range(12))
    expected = (10 - total % 10) % 10
    return int(value[12]) == expected


def _to_isbn13(isbn: str) -> str:
    if len(isbn) == 13:
        return isbn
    prefix = "978" + isbn[:9]
    total = sum(int(prefix[i]) * (1 if i % 2 == 0 else 3) for i in range(12))
    check = (10 - total % 10) % 10
    return prefix + str(check)


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
