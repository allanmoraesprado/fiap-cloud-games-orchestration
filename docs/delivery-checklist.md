# Delivery Checklist — FIAP Cloud Games (Phase 3)

Requirement → where it is satisfied → evidence. Phase 2 items remain valid (tag `phase-2`).

## API Gateway
- [x] Kong Gateway 3.9 **DB-less** as the official entry point — `docker-compose.yml` (`kong`), `k8s/kong.yaml` (NodePort 30080), config in `gateway/kong.yml`
- [x] Public routes without JWT: `/api/auth/register`, `/api/auth/login`
- [x] Protected routes with **JWT validated by Kong**: `/api/users/*`, `/api/games/*`, `/api/library/*`, `/api/payments/*` (`jwt` plugin, consumer keyed by `iss`, HS256 shared secret, `exp` verified)
- [x] Services keep validating the JWT (**defense in depth**) and own role/ownership authorization
- [x] Rate limiting (5 req/s, 120 req/min → 429), correlation id (`X-Correlation-ID`), Prometheus plugin — [`gateway.md`](gateway.md)
- [x] Evidence: 401 without/invalid token, 403/200 role checks, 429 burst — [`testing.md`](testing.md)

## Serverless (Notifications Function)
- [x] Phase 2 `notifications-api` **replaced** in the main flow by `fiap-cloud-games-notifications-function` (Azure Functions, .NET 8 isolated worker, Kafka trigger)
- [x] Consumes `fcg.users.created` and `fcg.payments.processed` with consumer group `notifications-function`
- [x] Logs `[WELCOME EMAIL]` and `[PURCHASE CONFIRMATION]`; rejected payments produce no e-mail; malformed messages are warnings
- [x] Runs locally with Azure Functions Core Tools (`func start`), as a Compose container and as a Kubernetes Deployment (official Functions base image)
- [x] Real Azure deployment documented **only** as a future improvement (Premium/Dedicated plan, Event Hubs/SASL_SSL, Key Vault, App Insights, KEDA)
- [x] `local.settings.json` git-ignored; `local.settings.example.json` with placeholders

## Observability — metrics
- [x] `/metrics` (prometheus-net) on UsersAPI, CatalogAPI, PaymentsAPI: default HTTP metrics + domain counters with low-cardinality labels (no PII)
- [x] Kong metrics on the Status API
- [x] Prometheus with static targets (Compose and Kubernetes) — `observability/prometheus/prometheus.yml`
- [x] Grafana provisioned from files, **FCG Overview** dashboard — `observability/grafana/`
- [x] Evidence: targets `up`, counters moving after the flow — [`observability.md`](observability.md), [`testing.md`](testing.md)

## Observability — centralized logs
- [x] Grafana **Loki** + **Alloy** (Docker discovery over the read-only Docker socket) collecting every Compose container, including the Notifications Function, Kong and infrastructure — `observability/loki/`, `observability/alloy/`
- [x] Grafana Loki datasource + **FCG Logs** dashboard (by service, by OrderId, e-mail markers, Kong access log)
- [x] Evidence: LogQL by `compose_service`, by OrderId across services, `[WELCOME EMAIL]` / `[PURCHASE CONFIRMATION]`
- [x] Kubernetes: `kubectl logs`; Loki/Alloy on Kubernetes documented as a future improvement (DaemonSet + RBAC) — [`kubernetes.md`](kubernetes.md)

## NoSQL (MongoDB)
- [x] PaymentsAPI persists the payment history in MongoDB 7: database `fcg_payments`, collection `payments`, one document per `orderId`, unique index, idempotent upsert
- [x] Protected `GET /api/payments/order/{orderId}` through Kong (owner or Admin; 403/404 otherwise)
- [x] PaymentsAPI independent from PostgreSQL; Compose service `mongo` and `k8s/mongo.yaml`
- [x] Evidence: documents for approved and rejected purchases, replay keeps one document — [`nosql.md`](nosql.md)

## Distributed cache (Redis)
- [x] CatalogAPI cache-aside on `GET /api/games`, `GET /api/games/{id}`, `GET /api/library/my-games` (and admin library) with 60 s TTL
- [x] Explicit invalidation: create/update/delete game; approved `PaymentProcessedEvent` invalidates the user's library
- [x] PostgreSQL fallback when Redis is down (BYPASS, warning), `X-FCG-Cache` diagnostic header
- [x] Compose service `redis` and `k8s/redis.yaml` — [`cache.md`](cache.md)

## Docker Compose
- [x] `docker compose up -d --build` runs the full Phase 3 stack (postgres, kafka + topics, redis, mongo, 3 APIs, notifications-function, kong, prometheus, grafana, loki, alloy)
- [x] `notifications-api` only under the `phase2-legacy` profile (single notification consumer)
- [x] Host ports parameterized in `.env.example`; in-network DNS names unchanged
- [x] Smoke test through Kong — `scripts/smoke-compose.ps1`

## Kubernetes (local)
- [x] Pure manifests in namespace `fcg`: Deployments, Services, ConfigMaps, one Secret; one replica; emptyDir
- [x] Redis, MongoDB, Kong (NodePort 30080), Prometheus (30090), Grafana (30300), Notifications Function (Deployment, no Service) added to the Phase 2 set
- [x] Gateway/observability ConfigMaps generated from the same files Compose uses (`apply-all`)
- [x] No cloud, no Helm, no Ingress, no service mesh; secrets are placeholders — [`kubernetes.md`](kubernetes.md)
- [x] Evidence: 12 pods Running + Job Completed, full flow through Kong, consumer groups LAG 0

## Security & secrets
- [x] Only local/dev placeholders committed (`.env.example`, `k8s/shared-secret.yaml`, `gateway/kong.yml`, `appsettings*.json`); `.env`, `local.settings.json` git-ignored
- [x] Kong Admin/Status APIs bound to localhost (Compose) / ClusterIP (Kubernetes); `/metrics` not routed by Kong
- [x] Azure Key Vault and other managed services mentioned **only** as future improvements

## Messaging (unchanged from Phase 2)
- [x] Apache Kafka single broker (KRaft); three topics; contracts unchanged and additive-only — [`../contracts/README.md`](../contracts/README.md)
- [x] At-least-once with idempotent consumers — [`event-flows.md`](event-flows.md)

## Quality & documentation
- [x] Unit tests: 71 in the main flow (21 + 22 + 15 + 13) + 2 legacy — [`testing.md`](testing.md)
- [x] READMEs for all six repositories; `notifications-api` README marks it as Phase 2 history
- [x] Architecture, event flows, gateway, cache, NoSQL, observability, Kubernetes, testing, demo script, final report — `docs/`
- [x] Milestone evidence transcripts kept locally (P3-M0 … P3-M7) and summarized in the docs

## Repositories
- [x] `fiap-cloud-games-users-api`, `fiap-cloud-games-catalog-api`, `fiap-cloud-games-payments-api`, `fiap-cloud-games-notifications-function`, `fiap-cloud-games-orchestration` (+ `fiap-cloud-games-notifications-api` as Phase 2 history)
- [x] Delivery = final commits pushed to `main` in every repository. Git tags were not required for the academic delivery and were not used in previous phases; creating a `phase-3` tag is optional and can be done later only as a versioning convenience (the `phase-2` tag exists from the Phase 3 kick-off, see [`final-report.md`](final-report.md))

## Video and final report
- [ ] Video recorded following [`demo-script.md`](demo-script.md) (12–15 min) — link in [`final-report.md`](final-report.md)
- [ ] Final report completed with student/group, Discord, documentation and video links — [`final-report.md`](final-report.md)

## Out of scope (by design)
- [x] No real cloud, no real payment/e-mail providers, no Key Vault implementation, no distributed tracing, no Alertmanager, no Helm/Ingress/mesh/CI-CD, Phase 1 monolith untouched
