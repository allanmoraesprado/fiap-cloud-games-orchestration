#!/usr/bin/env bash
# Measures the Redis cache effect on CatalogAPI read latency through the gateway, with repeated
# samples. Each round: an admin PUT of the same game (invalidates its cache entry), then
#   GET /api/games/{id}  -> MISS (PostgreSQL + cache SET), timed
#   GET /api/games/{id}  -> HIT  (Redis), timed
# Samples are classified by the X-FCG-Cache header (not by position) and summarized
# (min / median / mean / p95 / max, in ms). Calls are paced under the Kong rate limit.
#
# Usage: bash scripts/measure-cache.sh <gateway-url> <admin-email> <admin-password> [rounds]
# Works against Compose (http://localhost:8000), the local AKS rehearsal or AKS.
set -euo pipefail
base="${1%/}"; admin_email="$2"; admin_password="$3"; rounds="${4:-30}"
pace="${PACE_SECONDS:-0.7}"

token="$(curl -s -X POST "$base/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$admin_email\",\"password\":\"$admin_password\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[[ -n "$token" ]] || { echo "admin login failed"; exit 1; }
auth=(-H "Authorization: Bearer $token")

game="$(curl -s "${auth[@]}" "$base/api/games" | node -e '
const g=JSON.parse(require("fs").readFileSync(0)); const x=g.find(i=>i.title==="Cosmic Odyssey")||g[0];
process.stdout.write(JSON.stringify({id:x.id,title:x.title,description:x.description,genre:x.genre,price:x.price,releaseDate:x.releaseDate}))')"
id="$(printf '%s' "$game" | node -pe 'JSON.parse(require("fs").readFileSync(0)).id')"
body="$(printf '%s' "$game" | node -pe 'const g=JSON.parse(require("fs").readFileSync(0)); delete g.id; JSON.stringify(g)')"
echo "game $id, $rounds rounds, gateway $base"

samples="$(mktemp)"
timed_get() { # prints "<outcome> <seconds>"
  local hdr; hdr="$(mktemp)"
  local t; t="$(curl -s -o /dev/null -D "$hdr" -w '%{time_total}' "${auth[@]}" "$base/api/games/$id")"
  local outcome; outcome="$(grep -i '^x-fcg-cache:' "$hdr" | awk '{print $2}' | tr -d '\r')"
  rm -f "$hdr"; echo "${outcome:-NONE} $t"
}
for ((i = 1; i <= rounds; i++)); do
  curl -s -o /dev/null -X PUT "${auth[@]}" -H 'Content-Type: application/json' -d "$body" "$base/api/games/$id"; sleep "$pace"
  timed_get >> "$samples"; sleep "$pace"
  timed_get >> "$samples"; sleep "$pace"
done

node - "$samples" <<'JS'
const lines = require("fs").readFileSync(process.argv[2], "utf8").trim().split("\n");
const by = {};
for (const l of lines) { const [o, s] = l.split(" "); (by[o] ||= []).push(parseFloat(s) * 1000); }
const q = (a, p) => a[Math.min(a.length - 1, Math.ceil(p * a.length) - 1)];
console.log("outcome  n    min    median   mean     p95     max   (ms)");
const stats = {};
for (const [o, a] of Object.entries(by)) {
  a.sort((x, y) => x - y);
  const mean = a.reduce((s, x) => s + x, 0) / a.length;
  stats[o] = { median: q(a, 0.5), mean };
  console.log(`${o.padEnd(7)} ${String(a.length).padStart(3)} ${a[0].toFixed(1).padStart(7)} ${q(a, .5).toFixed(1).padStart(8)} ${mean.toFixed(1).padStart(8)} ${q(a, .95).toFixed(1).padStart(7)} ${a[a.length - 1].toFixed(1).padStart(7)}`);
}
if (stats.MISS && stats.HIT) {
  const d = stats.MISS.median - stats.HIT.median;
  console.log(`median MISS - HIT = ${d.toFixed(1)} ms (${(100 * d / stats.MISS.median).toFixed(1)}% of the MISS median)`);
}
JS
rm -f "$samples"
