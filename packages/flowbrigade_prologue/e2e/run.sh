#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
IMAGE="flowbrigade-prologue-e2e"
CONTAINER="flowbrigade-prologue-e2e-$RANDOM"
PORT="${FLOWBRIGADE_PROLOGUE_E2E_PORT:-18080}"
BASE_URL="http://127.0.0.1:${PORT}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

docker build -f "$ROOT/packages/flowbrigade_prologue/e2e/Dockerfile" -t "$IMAGE" "$ROOT"
docker run -d --rm --name "$CONTAINER" -p "127.0.0.1:${PORT}:8080" "$IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "${BASE_URL}/health" >/dev/null

limited_headers="$TMP_DIR/limited.headers"
limited_body="$TMP_DIR/limited.body"
limited_status="$(curl -sS -D "$limited_headers" -o "$limited_body" -w "%{http_code}" "${BASE_URL}/limited")"
test "$limited_status" = "200"
grep -qi '^RateLimit-Limit:' "$limited_headers"

denied_headers="$TMP_DIR/denied.headers"
denied_body="$TMP_DIR/denied.body"
denied_status="$(curl -sS -D "$denied_headers" -o "$denied_body" -w "%{http_code}" "${BASE_URL}/limited")"
test "$denied_status" = "429"
grep -qi '^Retry-After:' "$denied_headers"

deadline_headers="$TMP_DIR/deadline.headers"
deadline_body="$TMP_DIR/deadline.body"
deadline_status="$(curl -sS -D "$deadline_headers" -o "$deadline_body" -w "%{http_code}" "${BASE_URL}/deadline")"
test "$deadline_status" = "504"
grep -qi '^X-FlowBrigade-Deadline-Remaining-Ms:' "$deadline_headers"

login_headers="$TMP_DIR/login.headers"
login_body="$TMP_DIR/login.body"
login_status="$(curl -sS -X POST -d '' -H 'X-Account-ID: alice' -H 'X-Forwarded-For: 192.0.2.10' -D "$login_headers" -o "$login_body" -w "%{http_code}" "${BASE_URL}/login")"
test "$login_status" = "200"

login_denied_headers="$TMP_DIR/login-denied.headers"
login_denied_body="$TMP_DIR/login-denied.body"
login_denied_status="$(curl -sS -X POST -d '' -H 'X-Account-ID: alice' -H 'X-Forwarded-For: 192.0.2.10' -D "$login_denied_headers" -o "$login_denied_body" -w "%{http_code}" "${BASE_URL}/login")"
test "$login_denied_status" = "429"
grep -q 'Too many login attempts' "$login_denied_body"

echo "Prologue Docker E2E passed"
