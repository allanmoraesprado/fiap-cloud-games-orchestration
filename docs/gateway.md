# API Gateway (Kong) — FIAP Cloud Games (Phase 3)

Phase 3 adds **Kong Gateway 3.9 (OSS)** in **DB-less mode** as the **official external entry
point** for API calls. Routes, the JWT credential and the plugins are declared in
[`gateway/kong.yml`](../gateway/kong.yml) and loaded by the `kong` service in
`docker-compose.yml`. No Kong database, no Kong Manager, no Ingress Controller.

Direct service ports stay published for **development and Swagger** only; evaluators and
clients should call the platform through the gateway.

## URLs (host)

| Endpoint | URL | Notes |
|---|---|---|
| **Gateway proxy** | `http://localhost:8000` | Official entry point for `/api/*` |
| Gateway Admin API | `http://127.0.0.1:8001` | Bound to localhost; read-only in DB-less (inspection: `/routes`, `/plugins`, `/consumers`) |
| Gateway Status API | `http://127.0.0.1:8100/metrics` | Prometheus metrics (scraped in a later milestone) |
| UsersAPI (direct) | `http://localhost:8080/swagger` | Swagger UI + dev access |
| CatalogAPI (direct) | `http://localhost:8082/swagger` | Swagger UI + dev access |
| PaymentsAPI (direct) | `http://localhost:8083/health` | Health only |
| NotificationsAPI (direct, Phase 2 legacy) | `http://localhost:8081/health` | Still in Compose until the Notifications Function is wired in |

Swagger is **not** routed through Kong (`http://localhost:8000/swagger` → 404 `no Route matched`).

## Routes

Prefix matching with `strip_path: false`: the services receive exactly the paths they already
expose, so **no API changed**.

| Route | Path prefix | Upstream | JWT at Kong | Notes |
|---|---|---|---|---|
| `users-auth-public` | `/api/auth` | `users-api:8080` | **No** (public) | `POST /api/auth/register`, `POST /api/auth/login` |
| `users-protected` | `/api/users` | `users-api:8080` | **Yes** | Admin role enforced by UsersAPI (non-admin → 403) |
| `catalog-games` | `/api/games` | `catalog-api:8080` | **Yes** | Game catalog (admin writes enforced by CatalogAPI) |
| `catalog-library` | `/api/library` | `catalog-api:8080` | **Yes** | Purchase + library |
| `payments-protected` | `/api/payments` | `payments-api:8080` | **Yes** | Reserved for the payment-status endpoint (P3-M4); upstream answers 404 until then |

## Plugins

| Plugin | Scope | Configuration | Purpose |
|---|---|---|---|
| `jwt` | The four protected routes | `key_claim_name: iss`, `claims_to_verify: [exp]` | Validates the UsersAPI HS256 token at the edge |
| `rate-limiting` | Global | `second: 5`, `minute: 120`, `policy: local`, `limit_by: ip` | Low, demonstrable limit → HTTP 429 |
| `correlation-id` | Global | `X-Correlation-ID`, `generator: uuid`, `echo_downstream: true` | One id per request, forwarded upstream and echoed to the client |
| `prometheus` | Global | status code, latency, bandwidth, upstream health metrics | `kong_*` metrics on the Status/Admin API |

## JWT: validated in Kong **and** inside the services

**How Kong validates the current tokens without any service change.** UsersAPI issues
HS256 tokens with `iss = FiapCloudGames` (`Jwt__Issuer`). Kong's `jwt` plugin reads the
`iss` claim, finds the consumer credential whose `key` equals it (`consumers[fcg-users-api]`
in `kong.yml`), verifies the signature with that credential's `secret` (the shared
`Jwt__SecretKey`) and checks `exp`. Missing/invalid tokens are rejected by Kong with
**401** before reaching any service.

**Why the services still validate the token (defense in depth).**

- UsersAPI and CatalogAPI keep their JWT bearer validation unchanged (same shared secret,
  issuer and audience). A request that bypasses the gateway (direct ports, in-cluster calls,
  a misconfigured route) is still authenticated.
- Kong validates *signature + expiry* only. It does not check `aud` and knows nothing about
  roles: **authorization** (`Admin` vs `User`, ownership rules) is business logic and stays in
  the services (e.g. `GET /api/users` with a regular user's token passes Kong and gets **403**
  from UsersAPI).
- Evidence: a tampered token gets `401 {"message":"Invalid signature"}` from Kong and, when
  sent straight to CatalogAPI on port 8082, `401 Bearer error="invalid_token"` from the service.

**Secret handling (local-only).** The credential secret in `gateway/kong.yml` is the same
committed **local/dev placeholder** as `JWT__SECRETKEY` in `.env.example`,
`docker-compose.yml` defaults and `k8s/shared-secret.yaml`. Both must stay identical; if
you change `JWT__SECRETKEY` locally, update `kong.yml` too. Kong OSS 3.9 does **not** resolve
vault references (`{vault://env/...}`) in `jwt_secrets` (verified: the field is not
referenceable and the reference was used literally, producing `Invalid signature`), so the
value is literal. In production the gateway configuration would be rendered from a secret
store (e.g. Azure Key Vault) at deploy time — documented, not implemented. **No real secret
is committed.**

## Example calls (through the gateway)

> Windows: run these in **Git Bash**, or in PowerShell replace `curl` with `curl.exe`.

```bash
# Public routes (no token)
curl -X POST http://localhost:8000/api/auth/register -H "Content-Type: application/json" \
  -d '{"name":"Ana","email":"ana@fcg.com","password":"Ana@1234"}'
TOKEN=$(curl -s -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"ana@fcg.com","password":"Ana@1234"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

# Protected route without token -> 401 from Kong
curl -i http://localhost:8000/api/games

# Protected route with token -> 200 from CatalogAPI (note X-Correlation-ID and RateLimit headers)
curl -i http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN"

# Users route: regular user -> 403 (role enforced by UsersAPI); admin -> 200
curl -i http://localhost:8000/api/users -H "Authorization: Bearer $TOKEN"
ADMIN=$(curl -s -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"admin@fcg.com","password":"Admin@123"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -i http://localhost:8000/api/users -H "Authorization: Bearer $ADMIN"

# Purchase flow through the gateway
curl -X POST http://localhost:8000/api/library/acquire/<gameId> -H "Authorization: Bearer $TOKEN"   # 202 { orderId }
curl http://localhost:8000/api/library/my-games -H "Authorization: Bearer $TOKEN"                    # game appears after approval

# Payments route: 401 without token; 404 with token until the endpoint arrives in P3-M4
curl -i http://localhost:8000/api/payments/order/<orderId> -H "Authorization: Bearer $TOKEN"
```

### Triggering the rate limit (HTTP 429)

The global limit is **5 requests/second** (and 120/minute) per client IP. Fire a burst:

```bash
for i in $(seq 1 12); do curl -s -o /dev/null -w '%{http_code} ' http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN"; done; echo
# 200 200 200 200 200 429 429 429 429 429 429 429
```

A 429 response carries `X-RateLimit-Limit-Second: 5`, `X-RateLimit-Remaining-Second: 0`,
`RateLimit-Reset: 1`, `Retry-After: 1` and the body `{"message":"API rate limit exceeded"}`.
The window resets after one second, so the demo does not block the rest of the flow.

### Correlation id and metrics

- Every response through Kong carries `X-Correlation-ID: <uuid>`; the same header is forwarded
  to the upstream service. The services do not log it yet (candidate for the observability
  milestone).
- `curl http://127.0.0.1:8100/metrics | grep kong_http_requests_total` shows requests per
  service/route/status code, e.g. `code="401",source="kong"` (rejected at the edge) vs
  `code="200",source="service"`.

## Inspecting the gateway

```bash
curl http://127.0.0.1:8001/routes            # the five routes
curl http://127.0.0.1:8001/plugins           # jwt x4 (route-scoped) + rate-limiting, correlation-id, prometheus (global)
curl http://127.0.0.1:8001/consumers/fcg-users-api/jwt
docker compose logs -f kong                  # access log (one line per proxied request)
docker run --rm -e KONG_DATABASE=off -v "$PWD/gateway/kong.yml:/kong/declarative/kong.yml:ro" kong:3.9 kong config parse /kong/declarative/kong.yml
```

To apply a change to `gateway/kong.yml`: `docker compose restart kong` (or `docker compose up -d kong`).

## Limitations and what remains for later milestones

- `/api/payments/*` is routed and JWT-protected but the endpoint only exists from **P3-M4**
  (PaymentsAPI + MongoDB); today the upstream answers 404 after the token check.
- The Phase 2 `notifications-api` container is still in Compose; the Notifications Function
  (`fiap-cloud-games-notifications-function`, run with `func start`) replaces it when the
  Compose profile / Kubernetes wiring lands in later milestones.
- Rate limiting uses the `local` policy (per Kong node). A shared policy (Redis) is not needed
  for a single local node.
- Kong on **Kubernetes** (DB-less Deployment + ConfigMap + NodePort) comes in **P3-M7**;
  Prometheus/Grafana scraping of `kong_*` metrics in **P3-M5**; centralized logs in **P3-M6**.
- Host-port parametrization for Postgres/Redis (to avoid local port clashes) is planned for
  **P3-M3**, together with Redis.
- Startup: Kong is healthy before the .NET services finish booting (they have no container
  healthcheck); the first proxied calls may get a transient **503** for a few seconds.

## Validation evidence (2026-09-15)

| Check | Result |
|---|---|
| `kong config parse` on `gateway/kong.yml` | parse successful |
| Register + login through Kong | 201 / 200 (public routes, no token) |
| `GET /api/games` without token | 401 `{"message":"Unauthorized"}` from Kong |
| `GET /api/games` with token | 200 from CatalogAPI, `X-Correlation-ID` + `RateLimit-*` headers present |
| Tampered token via Kong / direct on 8082 | 401 `Invalid signature` (Kong) / 401 `invalid_token` (CatalogAPI) |
| `GET /api/users` no token / user / admin | 401 (Kong) / 403 (UsersAPI role) / 200 |
| `GET /api/library/my-games` with token | 200 |
| `POST /api/library/acquire/{id}` via Kong | 202 → PaymentsAPI Approved → CatalogAPI library write → `my-games` shows the game |
| `GET /api/payments/order/x` no token / with token | 401 (Kong) / 404 (PaymentsAPI, endpoint pending) |
| Burst of 12 requests | 5 × 200 then 7 × 429 with rate-limit headers |
| Swagger direct 8080 / 8082 vs via Kong | 200 / 200 vs 404 `no Route matched` |
| Direct call to 8082 without token | 401 from CatalogAPI (internal validation intact) |
| `http://127.0.0.1:8100/metrics` | `kong_http_requests_total{...}` per route/status |
| Application repositories | unchanged |
