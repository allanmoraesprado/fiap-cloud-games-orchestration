#!/usr/bin/env bash
# Continuous traffic through the gateway while a rolling update happens: GET /api/games with a
# throw-away user's token, one request every PACE_SECONDS (default 0.6 s = 100 req/min, under the
# Kong limit of 120 req/min per client IP). Prints one line per request (time, HTTP status,
# X-App-Version) and, at the end (after the duration or on Ctrl+C), the totals per HTTP status and
# per version. Any status other than 200 during a rollout means requests were lost.
#
# Usage: bash scripts/rolling-probe.sh <gateway-url> [duration-seconds]
#   e.g. bash scripts/rolling-probe.sh http://<label>.eastus2.cloudapp.azure.com 300
set -uo pipefail
base="${1:?gateway url required}"; base="${base%/}"
duration="${2:-300}"; pace="${PACE_SECONDS:-0.6}"

email="probe.$(date +%s)$RANDOM@fcg.com"; password="Probe#$(date +%s)a"
curl -s -o /dev/null -X POST "$base/api/auth/register" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Rolling probe\",\"email\":\"$email\",\"password\":\"$password\"}"
sleep "$pace"
token="$(curl -s -X POST "$base/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"$password\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[[ -n "$token" ]] || { echo "login failed (is the gateway up?)"; exit 1; }

declare -A by_status=() by_version=()
total=0
summary() {
  echo
  echo "requests: $total"
  for s in "${!by_status[@]}"; do echo "  HTTP $s: ${by_status[$s]}"; done
  for v in "${!by_version[@]}"; do echo "  version $v: ${by_version[$v]}"; done
  if [[ "${by_status[200]:-0}" -eq "$total" ]]; then echo "RESULT: every request answered 200"; else echo "RESULT: $((total - ${by_status[200]:-0})) request(s) not answered with 200"; fi
  exit 0
}
trap summary INT TERM

end=$((SECONDS + duration))
while (( SECONDS < end )); do
  out="$(curl -s -o /dev/null -D - -w 'STATUS %{http_code}\n' --max-time 10 \
    -H "Authorization: Bearer $token" "$base/api/games")"
  status="$(sed -n 's/^STATUS //p' <<<"$out")"
  version="$(grep -i '^x-app-version:' <<<"$out" | awk '{print $2}' | tr -d '\r')"
  version="${version:0:7}"; version="${version:-none}"
  total=$((total + 1))
  by_status[$status]=$(( ${by_status[$status]:-0} + 1 ))
  by_version[$version]=$(( ${by_version[$version]:-0} + 1 ))
  printf '%s  HTTP %s  X-App-Version %s\n' "$(date +%H:%M:%S)" "$status" "$version"
  sleep "$pace"
done
summary
