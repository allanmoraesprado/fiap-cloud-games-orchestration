# Distributed cache (Redis) — FIAP Cloud Games (Phase 3)

Phase 3 adds **Redis 7** as a **distributed cache** for the **CatalogAPI read side**. It is a
cache only: no authentication, no persistence, everything is rebuilt from PostgreSQL. The
implementation lives in `fiap-cloud-games-catalog-api` (`Infrastructure/Caching`); this page
documents the strategy and how to observe it locally.

## Why

`GET /api/games` and the user library listings are the hottest read paths of the platform and
change rarely. Serving them from Redis removes repeated PostgreSQL round-trips, keeps the
read model shared across CatalogAPI instances (a distributed cache, not an in-process one)
and gives a clear, demonstrable HIT/MISS behaviour for the delivery.

## Strategy: cache-aside with explicit invalidation

1. A read checks Redis first. **HIT** → the cached JSON is returned.
2. **MISS** → the query runs on PostgreSQL (Dapper read model / EF), the result is stored in
   Redis with an absolute TTL, then returned.
3. Writes do **not** update the cache; they **invalidate** the affected keys (next read is a MISS).
4. If Redis is unreachable the read is served from PostgreSQL (**BYPASS**), the failure is
   logged as a warning and the API keeps working. Invalidation failures are also warnings:
   the entry then expires by TTL (bounded staleness).

Only public catalog data and library listings are cached. **Never** JWT tokens, sessions or
authorization decisions — those stay in the services/gateway.

## Keys and TTL

All keys are prefixed with `fcg:catalog:` (Redis instance name).

| Key | Content | Populated by | TTL |
|---|---|---|---|
| `fcg:catalog:games:active` | Active games list (`GET /api/games`) | Dapper read model | 60 s |
| `fcg:catalog:game:{gameId}` | One game (`GET /api/games/{id}`) | EF (`GameService.GetAsync`) | 60 s |
| `fcg:catalog:library:{userId}` | A user's library (`GET /api/library/my-games`, `GET /api/library/user/{id}`) | Dapper read model | 60 s |

TTL comes from `Redis__DefaultTtlSeconds` (default 60 s: short on purpose, easy to demo).

## Invalidation rules

| Operation | Keys removed |
|---|---|
| `POST /api/games` (create) | `games:active` |
| `PUT /api/games/{id}` (update) | `games:active`, `game:{id}` |
| `DELETE /api/games/{id}` (soft delete) | `games:active`, `game:{id}` |
| `PaymentProcessedEvent` **Approved** consumed → game added to the library (or duplicate detected by the unique index) | `library:{userId}` |
| `PaymentProcessedEvent` **Rejected** | nothing |
| Approved but already owned (idempotent skip) | nothing |

## Configuration (CatalogAPI)

| Variable | Meaning | Compose value |
|---|---|---|
| `Redis__Enabled` | `false` swaps in a no-op cache (every read is BYPASS) | `true` |
| `Redis__ConnectionString` | StackExchange.Redis configuration; `abortConnect=false` + 1 s timeouts keep the API responsive when Redis is down | `redis:6379,abortConnect=false,connectTimeout=1000,syncTimeout=1000` |
| `Redis__DefaultTtlSeconds` | Absolute TTL for every entry | `60` |
| `Redis__ExposeOutcomeHeader` | Emits the diagnostic `X-FCG-Cache` header | `true` |

No secrets: local Redis has no password. In a cloud deployment the connection string would
come from a secret store (documented only).

## Observing HIT / MISS locally

Every CatalogAPI response that performed a cached read carries **`X-FCG-Cache: HIT | MISS | BYPASS`**
(diagnostic header, on by default locally). CatalogAPI also logs `Cache HIT`, `Cache MISS`,
`Cache SET`, `Cache INVALIDATED` and `Cache BYPASS` lines.

```bash
TOKEN=...   # login through Kong, see docs/gateway.md
curl -si http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN" | grep -i x-fcg-cache   # MISS
curl -si http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN" | grep -i x-fcg-cache   # HIT

docker compose exec redis redis-cli KEYS 'fcg:catalog:*'
docker compose exec redis redis-cli TTL fcg:catalog:games:active
docker compose logs catalog-api | grep -E "Cache (HIT|MISS|SET|INVALIDATED|BYPASS)"
```

Invalidation demo: as admin, `POST /api/games` → the next `GET /api/games` is a **MISS** and
lists the new game. Purchase demo: `POST /api/library/acquire/{gameId}` → after the approved
payment is consumed, the next `GET /api/library/my-games` is a **MISS** and shows the game.

Fallback demo: `docker compose stop redis` → `GET /api/games` still returns 200 with
`X-FCG-Cache: BYPASS` and a `Cache BYPASS ... Redis unavailable` warning in the CatalogAPI
log → `docker compose start redis` → MISS, then HIT again.

> Kong rate-limits 5 req/s; leave a short pause between calls when scripting the demo.

## Out of scope (by design)

No cache for UsersAPI/PaymentsAPI, no write-through, no Redis persistence, no cluster/sentinel.
Hit/miss/bypass and invalidation counters are exported to Prometheus
(`fcg_cache_requests_total`, `fcg_cache_invalidations_total`, see [observability.md](observability.md));
on Kubernetes Redis runs from `k8s/redis.yaml` with the same settings in the CatalogAPI ConfigMap.
