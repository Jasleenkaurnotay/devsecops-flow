import pytest

from app import validate_name


@pytest.mark.parametrize("name", ["Asha", "Mary-Jane O'Neil", "A"])
def test_valid_names(name):
    assert validate_name(name)


@pytest.mark.parametrize("name", ["", "   ", "1abc", None, 42, "x" * 65])
def test_invalid_names(name):
    assert not validate_name(name)
