"""Smoke test: hits a REAL deployment. Skipped unless BASE_URL is set.

Run after a deploy, e.g.:
    BASE_URL=http://localhost:8080 EXPECTED_SHA=abc1234 pytest -m smoke
"""
import os

import pytest
import requests

BASE_URL = os.environ.get("BASE_URL")
pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(not BASE_URL, reason="BASE_URL not set"),
]


def test_health_is_up():
    assert requests.get(f"{BASE_URL}/health", timeout=5).status_code == 200


def test_running_expected_commit():
    expected = os.environ.get("EXPECTED_SHA")
    if not expected:
        pytest.skip("EXPECTED_SHA not set")
    got = requests.get(f"{BASE_URL}/version", timeout=5).json()["version"]
    assert got == expected
