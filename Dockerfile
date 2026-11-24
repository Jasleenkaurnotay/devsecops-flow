# Build context is the repo root.  docker build -t student-portal:local .
# Stage 1: install dependencies (build tools never reach the final image).
FROM python:3.12-slim AS builder
WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: runtime. Production hardening you should be able to explain:
#  - numeric non-root UID (Kubernetes runAsNonRoot can verify a number, not a name)
#  - only the files the app needs, owned by that UID
#  - no package manager cache, no shell login for the user
FROM python:3.12-slim
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
WORKDIR /srv/app
COPY --from=builder /install /usr/local
COPY --chown=10001:10001 app/app.py app/wsgi.py ./
USER 10001
ENV PYTHONUNBUFFERED=1 DB_LINK=/tmp/students.db
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "wsgi:application"]
