#!/usr/bin/env bash
# End-to-end smoke test against a running deployment. Exercises the whole
# path - Nginx -> API -> PostgreSQL - through the public entry point.
#
# Usage: scripts/smoke-test.sh [base-url]      (default: http://localhost:8080)
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
API="${BASE_URL}/api/v1/todos"

status=""
body=""

# request METHOD URL [JSON_BODY] -> sets $status and $body
request() {
  local method="$1" url="$2" data="${3:-}" response
  local args=(--silent --show-error --max-time 10 --request "${method}" --write-out '\n%{http_code}')
  if [[ -n "${data}" ]]; then
    args+=(--header 'Content-Type: application/json' --data "${data}")
  fi
  response="$(curl "${args[@]}" "${url}")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
}

pass() { echo "  ok    $1"; }
fail() {
  echo "  FAIL  $1" >&2
  echo "        HTTP ${status}: ${body}" >&2
  exit 1
}

expect_status() {
  if [[ "${status}" == "$1" ]]; then pass "$2"; else fail "$2 (expected HTTP $1)"; fi
}

expect_body() {
  if [[ "${body}" == *"$1"* ]]; then pass "$2"; else fail "$2 (expected body to contain: $1)"; fi
}

echo "Smoke test against ${BASE_URL}"

request GET "${BASE_URL}/"
expect_status 200 "frontend is served"
expect_body "<title>TODO</title>" "frontend returns the application page"

request GET "${BASE_URL}/nginx-health"
expect_status 200 "nginx health endpoint"

request POST "${API}" '{"title":"smoke test todo","priority":"high"}'
expect_status 201 "create todo"
id="$(printf '%s' "${body}" | sed -n 's/.*"id":"\([0-9a-f-]\{36\}\)".*/\1/p')"
[[ -n "${id}" ]] || fail "create todo returns an id"

request GET "${API}/${id}"
expect_status 200 "read todo back from the database"
expect_body '"title":"smoke test todo"' "todo has the submitted title"

request PATCH "${API}/${id}" '{"completed":true}'
expect_status 200 "complete todo"
expect_body '"completed":true' "todo is marked completed"

request GET "${API}?status=completed&limit=100"
expect_status 200 "list completed todos"
expect_body "${id}" "completed list contains the todo"

request POST "${API}" '{"title":""}'
expect_status 400 "invalid input is rejected"
expect_body '"code":"VALIDATION_ERROR"' "validation error has a machine-readable code"

request DELETE "${API}/${id}"
expect_status 204 "delete todo"

request GET "${API}/${id}"
expect_status 404 "deleted todo is gone"

request GET "${BASE_URL}/metrics"
expect_status 404 "backend metrics are not exposed publicly"

request GET "${BASE_URL}/health/ready"
expect_status 404 "backend health endpoints are not exposed publicly"

echo "Smoke test passed"
