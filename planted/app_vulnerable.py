# PLANTED: code-level flaws for SAST (CodeQL / Sonar). Copy to app/ on a feature branch.
# Expected findings: SQL injection (string-built query), command injection (shell=True), debug server.
import sqlite3
import subprocess

from flask import Flask, request

app = Flask(__name__)


@app.get("/search")
def search():
    name = request.args.get("name", "")
    conn = sqlite3.connect("/tmp/students.db")
    rows = conn.execute("SELECT * FROM students WHERE name = '" + name + "'").fetchall()  # SQL injection
    return {"rows": [list(r) for r in rows]}


@app.get("/ping")
def ping():
    host = request.args.get("host", "localhost")
    out = subprocess.run("ping -c1 " + host, shell=True, capture_output=True)  # command injection
    return {"out": out.stdout.decode()}


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)  # Werkzeug debugger exposed
