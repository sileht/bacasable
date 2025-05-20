import random
import pytest

def test_stable_one():
    assert 2 + 2 == 4

def test_stable_two():
    assert "mergify" in "pytest-mergify"

def test_flaky():
    if random.randint(1, 5) == 1:
        pytest.fail("Random flaky failure")
