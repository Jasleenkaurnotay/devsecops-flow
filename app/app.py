"""Student Portal API: a deliberately small Flask app used for the DevSecOps pipeline lab.

The point of this app is to give the pipeline something real to build, test,
scan and deploy. Keep it small.
"""
import os
import re
import sqlite3
from contextlib import closing

from flask import Flask, jsonify, request

NAME_RE = re.compile(r"^[A-Za-z][A-Za-z .'-]{0,63}$")


def validate_name(name):
    """A name is a string of 1-64 chars, starting with a letter."""
    return isinstance(name, str) and bool(NAME_RE.match(name.strip()))


def create_app(db_link=None):
    app = Flask(__name__)
    # DB_LINK is an env var so tests can point at a throwaway SQLite file.
    db_path = db_link or os.environ.get("DB_LINK", "/tmp/students.db")

    def get_db():
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        return conn

    with closing(get_db()) as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS students ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "name TEXT NOT NULL, course TEXT NOT NULL)"
        )
        conn.commit()

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/version")
    def version():
        # GIT_SHA is injected at build/deploy time; this is how you prove
        # "the same image was promoted" from dev to staging to prod.
        return jsonify(
            version=os.environ.get("GIT_SHA", "dev"),
            env=os.environ.get("APP_ENV", "local"),
        )

    @app.get("/students")
    def list_students():
        with closing(get_db()) as conn:
            rows = conn.execute("SELECT id, name, course FROM students ORDER BY id").fetchall()
        return jsonify([dict(r) for r in rows])

    @app.post("/students")
    def add_student():
        body = request.get_json(silent=True) or {}
        name, course = body.get("name"), body.get("course")
        if not validate_name(name) or not isinstance(course, str) or not course.strip():
            return jsonify(error="invalid name or course"), 400
        with closing(get_db()) as conn:
            cur = conn.execute(
                "INSERT INTO students (name, course) VALUES (?, ?)",
                (name.strip(), course.strip()),
            )
            conn.commit()
            new_id = cur.lastrowid
        return jsonify(id=new_id, name=name.strip(), course=course.strip()), 201

    return app
