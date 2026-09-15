# Testing Evidence — FIAP Cloud Games (Phase 3)

## Unit tests

Run per repository with `dotnet test` (xUnit, FluentAssertions, Moq where needed). Totals
re-executed at the end of Phase 3 (all green, 0 warnings on build):

| Repository | Tests | Covers |
|---|---|---|
| UsersAPI | 21 | registration validation, duplicate e-mail (409), invalid login (401), JWT issuance, publish-on-register |
| CatalogAPI | 22 | game admin policy, validator, purchase-completion idempotency, **cache-aside** (hit/miss/remove/fallback/JSON round-trip), cached read model, cache invalidation on create/update/delete and on approved payment |
| PaymentsAPI | 15 | deterministic simulator + reasons, **processor** (persist + publish, rejected reason, replay keeps one document, persistence failure does not block publishing), **payment query** rules (404, owner, other user forbidden, Admin) |
| Notifications Function | 13 | e-mail formatters, Kafka envelope parser (valid / malformed envelope / malformed event / missing Value), both function handlers (valid, malformed without throwing, approved, rejected, case-insensitive status) |
| **Total (Phase 3 main flow)** | **71** | |
| NotificationsAPI (Phase 2 history) | 2 | message formatting — kept, not part of the main flow |

## Integration evidence (validated end-to-end)

The final state was validated end-to-end with
the smoke script. Both deployment targets exercised the full register → purchase → payment
query flow **through Kong**.

### Docker Compose

```powershell
docker compose up -d --build
.\scripts\smoke-compose.ps1        # register, login, games MISS/HIT, approved purchase, payment query,
                                   # library, rejected purchase, Prometheus targets, Loki notification logs
```

| Check | Observed |
|---|---|
| Gateway / JWT | public `/api/auth/*` 201/200; protected routes 401 without token (`{"message":"Unauthorized"}`), 401 `Invalid signature` with a tampered token; the same token sent straight to a service on its direct port is rejected by the service too (defense in depth); `GET /api/users` 403 for a regular user, 200 for Admin |
| Rate limit | burst of 12 requests → 5 × 200 then 7 × 429 with `X-RateLimit-*` / `Retry-After` headers |
| Cache (Redis) | `GET /api/games`, `GET /api/games/{id}`, `GET /api/library/my-games`: `X-FCG-Cache: MISS` then `HIT`; create/update/delete game invalidate list/entry; approved purchase invalidates the user's library; `docker compose stop redis` → 200 with `BYPASS` and a warning, back to MISS/HIT after `start` |
| Payment history (MongoDB) | approved and rejected purchases stored as one document each (`status`, `reason`, event ids, timestamps); replaying the same `OrderPlacedEvent` keeps one document (`updatedAt` refreshed); `GET /api/payments/order/{orderId}`: owner 200, another user 403, Admin 200, unknown 404 |
| Notifications Function | container (and `func start`) logs `[WELCOME EMAIL]` after registration and `[PURCHASE CONFIRMATION]` with the OrderId after approval; rejected payment logs "no confirmation e-mail sent"; malformed messages are warnings and the host keeps consuming |
| Metrics | `/metrics` 200 on the three APIs; Prometheus targets users-api, catalog-api, payments-api, kong (+ prometheus) all `up`; counters move with the flow (HTTP by service/code, cache outcomes, payment decisions/queries/history writes, events published/consumed, registrations/logins, Kong per route/code); Grafana datasource + **FCG Overview** provisioned |
| Centralized logs | Loki labels `compose_service`, `job`, `container_name`, `platform`; 13 compose services streaming; LogQL by service, by OrderId across catalog → payments → function → kong, by `[WELCOME EMAIL]` / `[PURCHASE CONFIRMATION]`; Grafana **FCG Logs** provisioned and queried through the datasource proxy |
| Kafka | consumer groups `payments-service`, `catalog-service`, `notifications-function` at **LAG 0**; `notifications-service` absent (legacy API not running) |

### Local Kubernetes (namespace `fcg`)

```powershell
.\k8s\build-images.ps1
.\k8s\apply-all.ps1
kubectl get pods,svc,configmap,secret -n fcg
```

| Check | Observed |
|---|---|
| Workloads | 12 pods Running (postgres, kafka, redis, mongo, users-api, catalog-api, payments-api, notifications-function, kong, prometheus, grafana) + `kafka-topics` Completed; 12 ConfigMaps; `fcg-secret` with placeholder keys |
| Gateway | `http://localhost:30080`: register 201, login 200, `GET /api/games` 401 without token, MISS then HIT with token |
| Purchase | approved 202 → payment query 200 Approved → Mongo document → library shows the game; admin-created 1500 game → rejected 202 → query 200 Rejected → Mongo document with reason |
| Function | pod logs `[WELCOME EMAIL]`, `[PURCHASE CONFIRMATION]` (approved), "no confirmation e-mail sent" (rejected) |
| Kafka | `payments-service`, `catalog-service`, `notifications-function` at LAG 0 on all partitions |
| Observability | Prometheus (30090) targets all `up`; Grafana (30300) with Prometheus datasource and FCG Overview; `/metrics` not reachable through Kong |
| Swagger | direct access through `kubectl port-forward` (development only) |

Centralized logs on Kubernetes are intentionally not implemented (`kubectl logs` is the
validation path); see [kubernetes.md](kubernetes.md).

### Kafka / consumer-group commands

```bash
# Compose:
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups
# Kubernetes:
kubectl exec -n fcg deploy/kafka -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups
```

## How to run all tests

```bash
# in each repository
dotnet test
```
