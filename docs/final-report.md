# FIAP Cloud Games — Tech Challenge Phase 3 — Final Delivery Report

> Draft prepared at the end of P3-M8. Replace every `<placeholder>` before submitting.

| Item | Value |
|---|---|
| Project | FIAP Cloud Games — Tech Challenge **Phase 3** |
| Student / group | `<student or group name(s)>` |
| RM / IDs | `<RM(s)>` |
| Discord username | `<discord username>` |
| Documentation (entry point) | `https://github.com/allanmoraesprado/fiap-cloud-games-orchestration` (README + `docs/`) — `<confirm/adjust link>` |
| Video | `<video link (12–15 min)>` |
| Delivery tag | `phase-3` on every repository (see "Release tags") |

## Repositories

| Repository | Role | Link |
|---|---|---|
| `fiap-cloud-games-orchestration` | Compose, Kubernetes, Kong config, observability config, contracts, docs (**start here**) | `https://github.com/allanmoraesprado/fiap-cloud-games-orchestration` |
| `fiap-cloud-games-users-api` | Identity: register, login, JWT, roles, `/metrics` | `https://github.com/allanmoraesprado/fiap-cloud-games-users-api` |
| `fiap-cloud-games-catalog-api` | Games, library, purchase orchestration, Redis cache, `/metrics` | `https://github.com/allanmoraesprado/fiap-cloud-games-catalog-api` |
| `fiap-cloud-games-payments-api` | Simulated payments, MongoDB payment history, payment status endpoint, `/metrics` | `https://github.com/allanmoraesprado/fiap-cloud-games-payments-api` |
| `fiap-cloud-games-notifications-function` | Serverless notifications (Azure Functions, Kafka trigger) | `https://github.com/allanmoraesprado/fiap-cloud-games-notifications-function` |
| `fiap-cloud-games-notifications-api` | Phase 2 notifications service — history only, replaced by the function | `https://github.com/allanmoraesprado/fiap-cloud-games-notifications-api` |

## Summary of the solution

FIAP Cloud Games is an event-driven microservices platform for a digital games store. Phase 2
delivered four .NET 8 services over Apache Kafka with PostgreSQL, Docker Compose and local
Kubernetes. Phase 3 evolves that platform with a **Kong API Gateway** validating JWT at the
edge, a **serverless Notifications Function** (Azure Functions with Kafka trigger) replacing the
always-running notifications container, **MongoDB** as the NoSQL store of the payment history,
**Redis** as the distributed cache of the catalog read model, **Prometheus + Grafana** for
metrics and **Loki + Alloy + Grafana** for centralized logs. Everything runs **locally** with
Docker Compose and on local Kubernetes, using placeholders for secrets; real cloud deployment
is documented only as a future improvement.

## Architecture overview

- **Entry point:** Kong 3.9 (DB-less, `gateway/kong.yml`). Public `/api/auth/register` and
  `/api/auth/login`; JWT required for `/api/users/*`, `/api/games/*`, `/api/library/*`,
  `/api/payments/*`; rate limiting (5 req/s), correlation id, Prometheus plugin.
- **APIs (.NET 8):** UsersAPI (PostgreSQL `fcg_users`, JWT issuer), CatalogAPI (PostgreSQL
  `fcg_catalog` + Redis cache), PaymentsAPI (MongoDB `fcg_payments`). All three validate the JWT
  again (defense in depth) and own role/ownership authorization.
- **Serverless:** Notifications Function (isolated worker) consumes `fcg.users.created` and
  `fcg.payments.processed` with consumer group `notifications-function`; logs `[WELCOME EMAIL]`
  and `[PURCHASE CONFIRMATION]`; rejected payments produce no e-mail.
- **Messaging:** Kafka (KRaft) with three topics and unchanged contracts; at-least-once with
  idempotent consumers (library unique index, payment upsert by `orderId`).
- **Observability:** `/metrics` on the APIs + Kong metrics → Prometheus → Grafana **FCG
  Overview**; container logs → Alloy → Loki → Grafana **FCG Logs** (Compose).
- **Deployment:** Docker Compose (full stack, host ports parameterized) and local Kubernetes
  (namespace `fcg`, pure manifests, Kong NodePort 30080, Prometheus 30090, Grafana 30300).

Diagram and details: `docs/architecture.md`, `docs/event-flows.md`.

## Technologies

.NET 8 (ASP.NET Core, EF Core + Npgsql, Dapper, Serilog, prometheus-net, StackExchange.Redis
via `IDistributedCache`, MongoDB.Driver 3, Confluent.Kafka) · Azure Functions v4 isolated
worker + Kafka extension (Core Tools 4) · Apache Kafka 3.9 (KRaft) · PostgreSQL 16 ·
MongoDB 7 · Redis 7 · Kong Gateway 3.9 · Prometheus 3.5 · Grafana 12 · Loki 3.5 · Grafana
Alloy 1.11 · Docker Compose · Kubernetes (Docker Desktop) · xUnit, Moq, FluentAssertions.

## Requirement-by-requirement mapping

| Phase 3 requirement | Implementation | Evidence / docs |
|---|---|---|
| API Gateway | Kong DB-less in Compose and Kubernetes; routes by prefix; official entry point | `docs/gateway.md` |
| JWT validated by the gateway | Kong `jwt` plugin (HS256, consumer keyed by `iss`, `exp`), services still validate | `docs/gateway.md`, `docs/testing.md` |
| Serverless function triggered by messaging | Notifications Function (Azure Functions, Kafka trigger) replacing NotificationsAPI | function README, `docs/architecture.md` |
| Observability — metrics | prometheus-net on the three APIs, Kong plugin, Prometheus, Grafana FCG Overview | `docs/observability.md` |
| Observability — centralized logs | Alloy (Docker discovery) → Loki → Grafana FCG Logs; filters by service, OrderId, e-mail markers | `docs/observability.md` |
| NoSQL persistence | MongoDB `fcg_payments.payments`, one document per order, unique index, upsert, payment status endpoint | `docs/nosql.md` |
| Distributed cache | Redis cache-aside in CatalogAPI, explicit invalidation, PostgreSQL fallback, `X-FCG-Cache` | `docs/cache.md` |
| Docker Compose | full stack in one command, host ports in `.env`, function as main notification path | `README.md` |
| Kubernetes | pure manifests in `fcg`, NodePorts, ConfigMaps generated from shared files, placeholders | `docs/kubernetes.md` |
| Tests and validation | 71 unit tests + Compose/Kubernetes end-to-end + smoke script | `docs/testing.md`, `scripts/smoke-compose.ps1` |
| Documentation | READMEs for the six repositories + `docs/` | `docs/delivery-checklist.md` |

## How to run with Docker Compose

```powershell
cd fiap-cloud-games-orchestration
cp .env.example .env               # optional; adjust *_HOST_PORT if a port is taken
docker compose up -d --build       # 14 containers
docker compose ps
.\scripts\smoke-compose.ps1        # end-to-end check through Kong
```

URLs: Kong `http://localhost:8000` · Grafana `http://localhost:3000` (`admin`/`admin`) ·
Prometheus `http://localhost:9090` · Loki `http://localhost:3100` · Swagger (direct)
`http://localhost:8080|8082|8083/swagger`. The Phase 2 `notifications-api` only starts with
`--profile phase2-legacy`.

## How to run with Kubernetes (local)

```powershell
cd fiap-cloud-games-orchestration
.\k8s\build-images.ps1
.\k8s\apply-all.ps1
kubectl get pods,svc,configmap,secret -n fcg
```

URLs: Kong `http://localhost:30080` · Grafana `http://localhost:30300` · Prometheus
`http://localhost:30090`. Logs: `kubectl -n fcg logs deploy/notifications-function`.
Tear down: `kubectl delete namespace fcg`.

## How to validate the flow

1. `POST /api/auth/register` and `POST /api/auth/login` through Kong (public).
2. `GET /api/games` twice with the token → `X-FCG-Cache: MISS` then `HIT`; without token → 401.
3. `POST /api/library/acquire/{gameId}` → 202 `{orderId}`.
4. `GET /api/payments/order/{orderId}` → 200 `Approved` (MongoDB document); another user 403; Admin 200.
5. `GET /api/library/my-games` → the game (cache invalidated by the approved payment).
6. Function logs: `[WELCOME EMAIL]`, `[PURCHASE CONFIRMATION]`; a game above 1000 → `Rejected`, no e-mail.
7. Grafana: FCG Overview (metrics) and FCG Logs (trace the `orderId` across services).
8. Kafka consumer groups `payments-service`, `catalog-service`, `notifications-function` at LAG 0.

Details and observed results: `docs/testing.md`.

## Local-only decisions and placeholders

- Kafka PLAINTEXT, single broker; Kong Admin/Status on localhost/ClusterIP; NodePorts instead of Ingress.
- Dev credentials only: PostgreSQL `fcg/fcg`, MongoDB `fcg/fcg`, Grafana `admin/admin`, JWT
  key `dev-only-change-me-please-min-32-characters-placeholder` (also embedded in
  `gateway/kong.yml`, which Kong OSS cannot read from a vault). `.env` and
  `local.settings.json` are git-ignored; no real secret is committed.
- Ephemeral storage on Kubernetes (`emptyDir`); no persistence for Prometheus/Loki.
- Azure Functions run locally (Core Tools / container / pod) with a storage placeholder; no cloud resources.

## Future cloud improvements (documented only)

Azure Function App (Premium/Dedicated; Kafka trigger unsupported on classic Consumption) with
Event Hubs (Kafka protocol) or managed Kafka over SASL_SSL and KEDA for scale-to-zero; Azure
Key Vault for secrets; RS256/JWKS; managed MongoDB (Cosmos DB for MongoDB / Atlas), managed
Redis, Kong on AKS or Konnect, managed Grafana/Prometheus, Loki on Kubernetes (Alloy
DaemonSet); outbox + retries/DLQ; multi-broker Kafka; PVCs; CI/CD.

## Release tags

After the final commits are pushed, tag every repository:

```bash
git tag -a phase-3 -m "Tech Challenge Phase 3 delivery"
git push origin phase-3
```

Repositories: `fiap-cloud-games-users-api`, `fiap-cloud-games-catalog-api`,
`fiap-cloud-games-payments-api`, `fiap-cloud-games-notifications-function`,
`fiap-cloud-games-notifications-api` (history, README note), `fiap-cloud-games-orchestration`.
