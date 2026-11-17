#!/usr/bin/env bash
# Post-deployment smoke test of one service through the public Kong gateway.
# Usage: smoke-service.sh <service> <gateway-url> <expected-version>
#   service: users-api | catalog-api | payments-api | notifications-function
# Creates a throw-away user (no stored credential needed), then checks the service's main
# endpoint and that responses come from the new version (X-App-Version == commit SHA).
set -euo pipefail
svc="$1"; base="${2%/}"; expected="$3"
ns="${K8S_NAMESPACE:-fcg}"
[[ -n "$base" ]] || { echo "gateway url is empty (repository variable GATEWAY_URL)"; exit 1; }

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; exit 1; }

# call <method> <path> [token] [json] -> sets STATUS, BODY, VERSION
call() {
  local method="$1" path="$2" token="${3:-}" body="${4:-}" hdr out
  hdr="$(mktemp)"; out="$(mktemp)"
  local args=(-s -o "$out" -D "$hdr" -w '%{http_code}' -X "$method" --max-time 20 "$base$path")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")
  STATUS="$(curl "${args[@]}" || echo 000)"
  BODY="$(cat "$out")"
  VERSION="$(grep -i '^x-app-version:' "$hdr" | tail -1 | cut -d' ' -f2 | tr -d '\r' || true)"
  rm -f "$hdr" "$out"
  sleep 0.3   # stay well below the gateway rate limit
}

# Retries until the response comes from the expected version (old pods may still be draining).
expect_version() { # expect_version <label> <method> <path> <token> <status>
  local label="$1" i
  for i in $(seq 1 20); do
    call "$2" "$3" "$4"
    if [[ "$STATUS" == "$5" && "$VERSION" == "$expected" ]]; then pass "$label -> $STATUS, X-App-Version $VERSION"; return 0; fi
    sleep 3
  done
  fail "$label: got HTTP $STATUS, X-App-Version '${VERSION:-none}' (expected $5 / $expected)"
}

if [[ "$svc" == "notifications-function" ]]; then
  # Event-driven, no HTTP route: the rollout already verified readiness; confirm the host loaded
  # the Kafka-triggered functions on the new image.
  kubectl -n "$ns" get deploy notifications-function -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q "$expected" \
    && pass "running image tag $expected" || fail "deployment image is not $expected"
  for i in $(seq 1 20); do
    if kubectl -n "$ns" logs deploy/notifications-function 2>/dev/null | grep -qE "Host started|Job host started|Found the following functions"; then
      pass "Functions host started"; exit 0
    fi
    sleep 5
  done
  fail "Functions host start not found in the logs"
fi

# Gateway reachable and protecting routes.
for i in $(seq 1 30); do
  call GET /api/games
  [[ "$STATUS" == "401" ]] && break
  sleep 5
done
[[ "$STATUS" == "401" ]] && pass "gateway up, /api/games without token -> 401" || fail "gateway not answering 401 (HTTP $STATUS)"

email="smoke.$svc.$(date +%s)$RANDOM@fcg.com"; password="Smoke#$(date +%s)a"
call POST /api/auth/register "" "{\"name\":\"Smoke $svc\",\"email\":\"$email\",\"password\":\"$password\"}"
[[ "$STATUS" == "201" ]] && pass "register -> 201" || fail "register: HTTP $STATUS $BODY"
call POST /api/auth/login "" "{\"email\":\"$email\",\"password\":\"$password\"}"
token="$(printf '%s' "$BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[[ "$STATUS" == "200" && -n "$token" ]] && pass "login -> 200 with JWT" || fail "login: HTTP $STATUS"

case "$svc" in
  users-api)
    for i in $(seq 1 20); do
      call POST /api/auth/login "" "{\"email\":\"$email\",\"password\":\"$password\"}"
      [[ "$STATUS" == "200" && "$VERSION" == "$expected" ]] && break
      sleep 3
    done
    [[ "$VERSION" == "$expected" ]] && pass "login served by version $VERSION" || fail "UsersAPI version '${VERSION:-none}' != $expected"
    ;;
  catalog-api)
    expect_version "GET /api/games" GET /api/games "$token" 200
    call GET "/api/games/search?q=cosmic" "$token"
    [[ "$STATUS" == "200" ]] && pass "GET /api/games/search?q=cosmic -> 200" || fail "search: HTTP $STATUS $BODY"
    ;;
  payments-api)
    expect_version "GET /api/payments/order/<unknown>" GET "/api/payments/order/$(cat /proc/sys/kernel/random/uuid 2>/dev/null || node -e 'console.log(crypto.randomUUID())')" "$token" 404
    ;;
  *) fail "unknown service $svc" ;;
esac
echo "Smoke test passed for $svc ($expected)"
