# FIAP Cloud Games — Orchestration

Local infrastructure **and** full-system runner for the FIAP Cloud Games event-driven
microservices platform (Phase 2, now evolving in **Phase 3**). From this repo,
`docker compose up -d --build` brings up PostgreSQL, Kafka, the microservices and the
**Kong API Gateway**.

This repository is the **orchestration** repo of a six-repository solution:

| Repository | Role |
|---|---|
| `fiap-cloud-games-users-api` | Identity: register, login, JWT, roles |
| `fiap-cloud-games-catalog-api` | Games, library, purchase orchestration |
| `fiap-cloud-games-payments-api` | Simulated payment processing |
| `fiap-cloud-games-notifications-api` | Console "e-mail" notifications (Phase 2; replaced by the function in Phase 3) |
| `fiap-cloud-games-notifications-function` | **Phase 3**: Kafka-triggered Azure Function (serverless notifications, run with `func start`) |
| **`fiap-cloud-games-orchestration`** | **Infra + gateway + full compose + docs (this repo)** |

The complete system runs on **Docker Compose** and on **local Kubernetes**
(Docker Desktop). This README is the **master entry point** for evaluators — start here.

---

## Documentation

| Doc | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | System overview, responsibilities, architecture diagram, design decisions, future improvements |
| [docs/gateway.md](docs/gateway.md) | **Phase 3** Kong API Gateway: routes, JWT at the edge, rate limit, correlation id, metrics, curl examples |
| [docs/cache.md](docs/cache.md) | **Phase 3** Redis distributed cache (CatalogAPI): strategy, keys, TTLs, invalidation, HIT/MISS demo |
| [docs/nosql.md](docs/nosql.md) | **Phase 3** MongoDB (PaymentsAPI): payment history document, idempotent upsert, payment-status query through Kong |
| [docs/observability.md](docs/observability.md) | **Phase 3** Prometheus + Grafana: scraped targets, metrics per service, FCG Overview dashboard, validation |
| [docs/event-flows.md](docs/event-flows.md) | Registration & purchase sequence diagrams, topics, consumer groups, idempotency |
| [contracts/README.md](contracts/README.md) | Canonical event contracts (`UserCreatedEvent`, `OrderPlacedEvent`, `PaymentProcessedEvent`) |
| [docs/testing.md](docs/testing.md) | Unit tests (37) + validated Compose/Kubernetes evidence |
| [docs/delivery-checklist.md](docs/delivery-checklist.md) | Requirement → where satisfied |
| [docs/demo-script.md](docs/demo-script.md) | Video/demo roteiro |

---

## What the system provides

- **PostgreSQL 16** — two logical databases: `fcg_users`, `fcg_catalog`.
- **Apache Kafka 3.9** — single broker, **KRaft (no Zookeeper)**.
  - internal listener `kafka:9092` (used by the service containers)
  - host listener `localhost:29092` (host-run dev)
- **Three topics**: `fcg.users.created`, `fcg.orders.placed`, `fcg.payments.processed`
  (1 partition, RF 1) pre-created by `kafka-init`.
- **Four microservices** built from the sibling repos, wired to `kafka:9092` and
  `postgres:5432`, sharing a JWT secret between UsersAPI and CatalogAPI.
- **Canonical event contracts**: [`contracts/README.md`](contracts/README.md).
- **Kong API Gateway 3.9 (DB-less)** — Phase 3 official entry point on `http://localhost:8000`:
  JWT validated at the edge on protected routes, rate limiting, correlation id and Prometheus
  metrics. Declarative config in [`gateway/kong.yml`](gateway/kong.yml); details in
  [docs/gateway.md](docs/gateway.md).
- **Redis 7** — Phase 3 distributed cache for the CatalogAPI read model (games list, game by
  id, user library) with short TTLs, explicit invalidation and PostgreSQL fallback. Details in
  [docs/cache.md](docs/cache.md).
- **MongoDB 7** — Phase 3 NoSQL database of PaymentsAPI: payment history in
  `fcg_payments.payments` (one document per order, idempotent upsert) and the protected
  `GET /api/payments/order/{orderId}` query. Details in [docs/nosql.md](docs/nosql.md).
- **Prometheus + Grafana** — Phase 3 observability: `/metrics` on the three APIs
  (prometheus-net, HTTP + domain counters), Kong metrics, Prometheus with static targets and a
  Grafana provisioned automatically with the **FCG Overview** dashboard
  (`observability/`). Centralized logs (Loki + Alloy) follow in P3-M6. Details in
  [docs/observability.md](docs/observability.md).

Single-broker, RF 1, single-partition are deliberate **MVP** choices.

---

## Prerequisites

- Docker Desktop (Docker Engine running) + Docker Compose v2.
- **The four service repos must be cloned as siblings of this repo** (same parent
  folder), because the compose build contexts point at `../fiap-cloud-games-*`:
  ```
  <parent>/
  ├── fiap-cloud-games-users-api
  ├── fiap-cloud-games-catalog-api
  ├── fiap-cloud-games-payments-api
  ├── fiap-cloud-games-notifications-api
  └── fiap-cloud-games-orchestration   (this repo)
  ```

---

## Run the full system

```bash
cp .env.example .env          # optional; compose has safe defaults
docker compose up -d --build  # builds the 4 service images + starts everything
```

`kafka-init` is a one-shot job that creates the topics and exits `0` — expected.

### Host ports

Every published port is parameterized in `.env` (`*_HOST_PORT`, `KONG_*_PORT`, see
[`.env.example`](.env.example)). Only the **host** side changes; containers keep their internal
ports and keep talking to each other through the compose DNS names. If 5432 or 6379 are
already taken on your machine, set e.g. `POSTGRES_HOST_PORT=5433` / `REDIS_HOST_PORT=6380`
in `.env` and run the stack normally. `KAFKA_HOST_PORT` also updates the advertised host
listener (`localhost:<port>`), so host-run clients such as the Notifications Function must use
the same value.

| Variable | Default | Variable | Default |
|---|---|---|---|
| `POSTGRES_HOST_PORT` | 5432 | `USERS_API_HOST_PORT` | 8080 |
| `REDIS_HOST_PORT` | 6379 | `CATALOG_API_HOST_PORT` | 8082 |
| `MONGO_HOST_PORT` | 27017 | `PAYMENTS_API_HOST_PORT` | 8083 |
| `KAFKA_HOST_PORT` | 29092 | `NOTIFICATIONS_API_HOST_PORT` | 8081 |
| `KONG_PROXY_PORT` | 8000 | `KONG_ADMIN_PORT` | 8001 |
| `KONG_STATUS_PORT` | 8100 | `PROMETHEUS_HOST_PORT` | 9090 |
| `GRAFANA_HOST_PORT` | 3000 | | |

Stop:
```bash
docker compose down           # keeps the postgres volume
docker compose down -v        # also removes the volume (forces DB re-init)
```

### Service URLs (host)

| Service | URL | Notes |
|---|---|---|
| **API Gateway (Kong)** | **http://localhost:8000** | **Official entry point** for `/api/*` — public: `/api/auth/*`; JWT required: `/api/users/*`, `/api/games/*`, `/api/library/*`, `/api/payments/*` |
| Kong Admin / Status | http://127.0.0.1:8001 · http://127.0.0.1:8100/metrics | localhost only; inspection + Prometheus metrics |
| UsersAPI (direct) | http://localhost:8080/swagger | Swagger + dev only |
| CatalogAPI (direct) | http://localhost:8082/swagger | Swagger + dev only |
| NotificationsAPI (direct) | http://localhost:8081/health | Phase 2 legacy consumer (see logs) |
| PaymentsAPI (direct) | http://localhost:8083/swagger | Swagger + dev only; payment history query |
| Redis (direct) | `localhost:6379` (`REDIS_HOST_PORT`) | cache inspection with `redis-cli` (see [docs/cache.md](docs/cache.md)) |
| MongoDB (direct) | `localhost:27017` (`MONGO_HOST_PORT`) | `fcg_payments` inspection with `mongosh` (see [docs/nosql.md](docs/nosql.md)) |
| **Grafana** | http://localhost:3000 | `admin` / `admin` (dev placeholders); dashboard **FCG → FCG Overview** (see [docs/observability.md](docs/observability.md)) |
| Prometheus | http://localhost:9090 | targets: users-api, catalog-api, payments-api, kong |
| API metrics (direct) | http://localhost:8080/metrics · :8082/metrics · :8083/metrics | prometheus-net, not routed by Kong |

Swagger UI is served by the services on their direct ports only (not through Kong).
URLs above use the default host ports; adjust if you changed them in `.env`.

---

## Demo flow (through the gateway)

1. `POST http://localhost:8000/api/auth/register` → 201 (public route) → **welcome e-mail**
   in `docker compose logs notifications-api` (or in the Notifications Function terminal).
2. `POST http://localhost:8000/api/auth/login` → copy the token (public route).
3. `GET http://localhost:8000/api/games` **without** token → **401** from Kong; **with** the
   token → 200 (Kong validates the JWT at the edge, then CatalogAPI validates it again).
   Call it twice: the response header `X-FCG-Cache` goes **MISS** → **HIT** (Redis cache).
4. `POST http://localhost:8000/api/library/acquire/{gameId}` → **202** `{ orderId }`.
5. `GET http://localhost:8000/api/library/my-games` → the game appears (`X-FCG-Cache: MISS`
   right after the approved payment invalidated the library entry, then HIT).
6. `GET http://localhost:8000/api/payments/order/{orderId}` → 200 with `status: Approved` and
   the reason (payment history from MongoDB; another user gets 403, Admin 200).
7. Burst 12 calls to `GET /api/games` → **429** after the 5th (rate limit, see [docs/gateway.md](docs/gateway.md)).
8. Open Grafana (`http://localhost:3000`, `admin`/`admin`) → **FCG Overview**: request rates,
   Kong routes and 401/429, cache HIT/MISS, payment decisions and queries, Kafka events.
9. Watch the chain: `docker compose logs -f kong users-api catalog-api payments-api notifications-api`.

The same calls work on the direct ports (8080/8082) for development.

Seeded users: `admin@fcg.com / Admin@123`, `user@fcg.com / User@123`.

---

## Validate

```bash
docker compose ps                       # infra healthy, kafka-init Exited(0), 4 services Up

# topics / databases
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
docker compose exec postgres psql -U fcg -d postgres -c "\l"

# event flow + consumer groups (LAG 0)
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic fcg.payments.processed --from-beginning --timeout-ms 5000
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group catalog-service
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notifications-service
```

> **Windows note:** run the `docker compose exec kafka ...` commands from
> **PowerShell** or **CMD**. In Git Bash (MSYS) the leading `/opt/...` argument is
> auto-rewritten to a Windows path; if you must use Git Bash, prefix it with an
> extra slash (`//opt/kafka/bin/...`).

---

## Kubernetes (local)

Run the same system on **local Kubernetes** (Docker Desktop Kubernetes recommended).
Manifests use the **hybrid** layout: each service repo has its own `/k8s`
(Deployment + Service + ConfigMap); this repo's `/k8s` holds shared infrastructure
(namespace, Kafka, PostgreSQL, shared ConfigMap/Secret) and the apply scripts. All
resources live in the `fcg` namespace.

> Enable Kubernetes in Docker Desktop (Settings → Kubernetes → Enable) first, and
> stop the compose stack (`docker compose down`) so ports 8080/8082 are free for
> port-forwarding. The four service repos must be cloned as siblings of this repo.

```powershell
# PowerShell is the primary path on Windows
.\k8s\build-images.ps1     # build the 4 images (Docker Desktop shares the image store; no load step)
.\k8s\apply-all.ps1        # namespace -> shared config/secret -> postgres+kafka -> topics Job -> services
```
Shell equivalents: `k8s/build-images.sh`, `k8s/apply-all.sh`.

Validate:
```powershell
kubectl get pods -n fcg
kubectl get svc  -n fcg
kubectl get configmap,secret -n fcg

# access UsersAPI + CatalogAPI (each in its own terminal)
kubectl port-forward -n fcg svc/users-api   8080:8080
kubectl port-forward -n fcg svc/catalog-api 8082:8080

# Kafka / consumer-group evidence
$KPOD = kubectl get pod -n fcg -l app=kafka -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group catalog-service
```

Tear down: `kubectl delete namespace fcg`.

Secrets in `k8s/shared-secret.yaml` are **local/development placeholders only**. In
production they would come from a secret manager (e.g. **Azure Key Vault**) — a
documented future improvement, not integrated in this MVP.

---

## Configuration reference

Values come from environment variables (see [`.env.example`](.env.example)); only
**local/development placeholders** are committed. Compose supplies fallback defaults,
so it runs with or without a `.env`. The same .NET config keys are provided two ways:
Compose `environment:` and Kubernetes ConfigMaps/Secret.

| Service | Config keys |
|---|---|
| `users-api` | `ConnectionStrings__Postgres` → `fcg_users` · `Jwt__SecretKey/Issuer/Audience` · `Kafka__BootstrapServers` · `Kafka__UserCreatedTopic` |
| `catalog-api` | `ConnectionStrings__Postgres` → `fcg_catalog` · `Jwt__SecretKey/Issuer/Audience` · `Kafka__BootstrapServers` · `Kafka__OrderPlacedTopic` · `Kafka__PaymentProcessedTopic` · `Kafka__PaymentsConsumerGroup` · `Redis__Enabled` · `Redis__ConnectionString` · `Redis__DefaultTtlSeconds` · `Redis__ExposeOutcomeHeader` |
| `payments-api` | `Kafka__BootstrapServers` · `Kafka__OrderPlacedTopic` · `Kafka__PaymentProcessedTopic` · `Kafka__ConsumerGroup` · `Payment__RejectAboveAmount` · `Mongo__ConnectionString` → `fcg_payments` · `Mongo__DatabaseName` · `Mongo__PaymentsCollectionName` · `Jwt__SecretKey/Issuer/Audience` |
| `notifications-api` | `Kafka__BootstrapServers` · `Kafka__UserCreatedTopic` · `Kafka__PaymentProcessedTopic` · `Kafka__ConsumerGroup` |

- **In-network names:** services use `kafka:9092`, `postgres:5432`, `redis:6379` and `mongo:27017` (never `localhost`).
- **Kubernetes:** a shared `fcg-config` (JWT issuer/audience, Kafka bootstrap) + a shared `fcg-secret` (JWT key, Postgres password) + a per-service ConfigMap; the DB password is injected from the Secret and never duplicated.
- No container healthchecks on the .NET services (the `aspnet` image lacks curl); startup order is handled by `depends_on` (Compose) / `readinessProbe` (k8s) plus the services' retry/resilience.

## Security & secrets

- **Authentication:** shared symmetric **JWT** (HMAC-SHA256). UsersAPI issues tokens; CatalogAPI validates them locally with the **same** `SecretKey`/`Issuer`/`Audience` — no call to UsersAPI. Passwords are stored as **PBKDF2** hashes.
- **Gateway (Phase 3):** Kong validates the same token at the edge on protected routes (`jwt` plugin, consumer credential keyed by the `iss` claim). The services keep validating it (defense in depth) and own all role/ownership authorization. The credential secret in `gateway/kong.yml` is the same committed dev placeholder as `JWT__SECRETKEY` and must be kept in sync with it — see [docs/gateway.md](docs/gateway.md).
- **Placeholders only:** `JWT__SECRETKEY`, the Postgres credentials and the MongoDB root credentials are development placeholders in `.env.example` and `k8s/shared-secret.yaml`. `.gitignore` excludes `.env`/secrets; **no real secrets are committed**.
- Local Kafka is **PLAINTEXT** (local-only); containers run as **non-root**.
- **Future production improvement:** replace the placeholder Kubernetes Secret with a managed secret store such as **Azure Key Vault** — documented only, **not implemented** in this MVP.

---

## Repository layout

```
fiap-cloud-games-orchestration/
├── docker-compose.yml          # postgres + kafka + kafka-init + redis + mongo + 4 services + kong + prometheus + grafana
├── .env.example                # config template (placeholders + host ports)
├── .gitignore · README.md
├── gateway/kong.yml            # Kong DB-less declarative config (routes, JWT, plugins)
├── observability/              # prometheus/prometheus.yml · grafana/provisioning (datasource, dashboards) · grafana/dashboards/fcg-overview.json
├── db/init/01-create-databases.sql   # creates fcg_users + fcg_catalog
├── k8s/                        # shared infra manifests + build/apply scripts
│   ├── namespace.yaml · shared-config.yaml · shared-secret.yaml
│   ├── postgres.yaml · kafka.yaml · kafka-topics-job.yaml
│   └── build-images.ps1/.sh · apply-all.ps1/.sh
├── contracts/README.md         # canonical event-contract reference
└── docs/                        # architecture · gateway · cache · nosql · observability · event-flows · testing · delivery-checklist · demo-script
```

---

## Status

Phase 2 is **delivery-ready** (tag `phase-2`): four event-driven microservices over Kafka,
running via Docker Compose and on local Kubernetes, with per-service databases, a shared
JWT, unit tests, and full documentation. See [docs/delivery-checklist.md](docs/delivery-checklist.md).

**Phase 3 in progress:** P3-M1 Notifications Function (own repository, `func start`),
P3-M2 Kong API Gateway (this repo, Compose), P3-M3 Redis cache + host-port parameterization,
P3-M4 MongoDB payment history and P3-M5 Prometheus + Grafana metrics are done. Next: Loki +
Alloy centralized logs (P3-M6), Kubernetes updates and final docs.
