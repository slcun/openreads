from douban_isbn_proxy.isbn import normalize_isbn, same_edition


def test_normalize_isbn_removes_formatting_and_uppercases_x():
    assert normalize_isbn(" 0-306-40615-2 ") == "0306406152"
    assert normalize_isbn("978-0-306-40615-7") == "9780306406157"


def test_same_edition_accepts_equivalent_isbn_10_and_13():
    assert same_edition("0306406152", "9780306406157") is True


def test_normalize_isbn_rejects_a_bad_checksum():
    assert normalize_isbn("9780306406158") is None
