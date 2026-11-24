import pytest

from app import create_app


@pytest.fixture()
def client(tmp_path):
    # Throwaway SQLite file per test: no shared state, no cluster, no AWS.
    app = create_app(db_link=str(tmp_path / "test.db"))
    return app.test_client()


def test_health(client):
    assert client.get("/health").get_json() == {"status": "ok"}


def test_add_then_list(client):
    r = client.post("/students", json={"name": "Asha", "course": "DevOps"})
    assert r.status_code == 201
    listed = client.get("/students").get_json()
    assert [s["name"] for s in listed] == ["Asha"]


def test_rejects_bad_input(client):
    r = client.post("/students", json={"name": "1bad", "course": "DevOps"})
    assert r.status_code == 400
    assert client.get("/students").get_json() == []


def test_version_reads_env(client, monkeypatch):
    monkeypatch.setenv("GIT_SHA", "abc1234")
    monkeypatch.setenv("APP_ENV", "dev")
    assert client.get("/version").get_json() == {"version": "abc1234", "env": "dev"}
