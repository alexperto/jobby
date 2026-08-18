from app.dedup import dedup_key


def test_identical_values_produce_the_same_key():
    a = dedup_key("Acme Corp", "Senior Engineer", "Remote")
    b = dedup_key("Acme Corp", "Senior Engineer", "Remote")
    assert a == b


def test_case_and_whitespace_differences_are_treated_as_the_same_key():
    a = dedup_key("Acme Corp", "Senior Engineer", "New York")
    b = dedup_key("  acme   corp ", "SENIOR ENGINEER", "new york")
    assert a == b


def test_a_different_location_produces_a_different_key():
    a = dedup_key("Acme Corp", "Senior Engineer", "New York")
    b = dedup_key("Acme Corp", "Senior Engineer", "Remote")
    assert a != b
