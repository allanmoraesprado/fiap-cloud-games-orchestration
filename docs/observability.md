# Observability — FIAP Cloud Games (Phase 3)

Phase 3 makes the platform observable with **Grafana as the single visualization platform**:

| Signal | Producer | Collector / store | Where to look |
|---|---|---|---|
| **Metrics** (P3-M5) | `/metrics` on UsersAPI, CatalogAPI, PaymentsAPI (`prometheus-net`); Kong `prometheus` plugin | **Prometheus** (static targets, 5 s scrape) | Grafana → **FCG Overview** |
| **Logs** (P3-M6) | stdout/stderr of every container (APIs, Kong, Notifications Function, infrastructure) | **Grafana Alloy** (Docker discovery) → **Loki** | Grafana → **FCG Logs** / Explore |

Everything lives under `observability/` and is **provisioned from files**: datasources
(Prometheus, Loki) and both dashboards appear automatically, no UI configuration.
Distributed tracing is intentionally out of scope.

## How this satisfies the Phase 3 observability requirement

| Requirement | Where |
|---|---|
| Metrics per service | `/metrics` on the three APIs: default HTTP metrics + domain counters (low-cardinality labels only) |
| Gateway metrics | Kong `prometheus` plugin on the Status API (`kong:8100/metrics`) |
| Metrics collection | Prometheus (`observability/prometheus/prometheus.yml`) |
| **Centralized logs** | Alloy tails all compose containers through the Docker API and ships them to Loki (`observability/alloy/config.alloy`, `observability/loki/loki.yml`) |
| Serverless function logs centralized | The Notifications Function runs as a compose container; its `[WELCOME EMAIL]` / `[PURCHASE CONFIRMATION]` lines are queryable in Loki like any other service |
| Visualization | Grafana with the **FCG Overview** (metrics) and **FCG Logs** (logs) dashboards, both provisioned |

## URLs and credentials (local/dev only)

| Component | URL | Notes |
|---|---|---|
| **Grafana** | `http://localhost:3000` (`GRAFANA_HOST_PORT`) | login `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` (defaults `admin` / `admin`, placeholders from `.env.example`) |
| Dashboards | Grafana → Dashboards → folder **FCG** | **FCG Overview** (uid `fcg-overview`) and **FCG Logs** (uid `fcg-logs`) |
| Explore | Grafana → Explore → datasource **Loki** | ad-hoc LogQL |
| Prometheus | `http://localhost:9090` (`PROMETHEUS_HOST_PORT`) | Status → Targets shows the five jobs |
| Loki | `http://localhost:3100` (`LOKI_HOST_PORT`) | HTTP API only (`/ready`, `/loki/api/v1/...`), no UI |
| Alloy UI | `http://127.0.0.1:12345` (`ALLOY_HOST_PORT`, localhost only) | component graph and health (`discovery.docker`, `loki.source.docker`, `loki.write`) |
| API metrics | `http://localhost:8080/metrics` · `:8082/metrics` · `:8083/metrics` | direct ports only |
| Kong metrics | `http://127.0.0.1:8100/metrics` | Status API, localhost only |

## Metrics (Prometheus)

Scraped targets: `users-api:8080`, `catalog-api:8080`, `payments-api:8080`, `kong:8100`, and
Prometheus itself. Retention 2 days, no persistent volume, no Alertmanager, no Kubernetes
service discovery.

**Default (prometheus-net):** `http_requests_received_total{code,method,controller,action}`,
`http_request_duration_seconds` (histogram), `http_requests_in_progress`, plus `dotnet_*` /
`process_*`.

**Custom counters** (never user ids, e-mails, order or game ids in labels):

| Service | Metric | Labels |
|---|---|---|
| UsersAPI | `fcg_users_registrations_total` | — |
| UsersAPI | `fcg_users_login_attempts_total` | `result`: success, failure |
| Users/Catalog/Payments | `fcg_events_published_total` | `topic`, `result`: success, failure |
| Catalog/Payments | `fcg_events_consumed_total` | `topic`, `result`: processed, malformed |
| CatalogAPI | `fcg_catalog_payments_consumed_total` | `status`: approved, rejected, other |
| CatalogAPI | `fcg_catalog_library_grants_total` | `result`: added, already_owned, duplicate, rejected |
| CatalogAPI | `fcg_cache_requests_total` | `outcome`: hit, miss, bypass |
| CatalogAPI | `fcg_cache_invalidations_total` | `target`: games, game, library |
| PaymentsAPI | `fcg_payments_decisions_total` | `status`: approved, rejected |
| PaymentsAPI | `fcg_payments_history_writes_total` | `result`: inserted, updated, failed |
| PaymentsAPI | `fcg_payments_queries_total` | `result`: found, not_found, forbidden |
| Kong | `kong_http_requests_total{service,route,code,source}`, `kong_request_latency_ms_*`, `kong_bandwidth_bytes`, `kong_upstream_target_health` | `source="kong"` = answered at the edge (401/429) |

The **FCG Overview** dashboard shows request rate and status codes by service, p95 latency,
Kong routes and edge rejections, cache hit/miss/bypass and hit ratio, invalidations, payment
decisions/queries/history writes, registrations and logins, library grants, Kafka events
published/consumed and the scrape targets. Stat panels use `increase(...[$__range])`.

## Logs (Loki + Alloy)

**How collection works.** `alloy` mounts the Docker socket **read-only** and runs three
components (`observability/alloy/config.alloy`):

1. `discovery.docker` lists the running containers through the Docker API.
2. `discovery.relabel` keeps only containers of the `fcg-orchestration` compose project and
   derives the labels `compose_service` (service name in `docker-compose.yml`), `job`
   (`fcg/<service>`) and `container_name`; every stream also carries `platform="fcg"`
   (Loki adds `service_name` automatically).
3. `loki.source.docker` tails stdout/stderr of those containers (no file mounts, no host
   logs) and `loki.write` pushes to `http://loki:3100`.

Applications keep writing to stdout/stderr as before (Serilog console in the APIs, the
Functions host console in the function, nginx access log in Kong); **no Loki sink was added
to application code**. Loki runs single-binary with filesystem storage and no
authentication; logs live as long as the container (no volume).

**Labels available:** `platform`, `compose_service`, `job`, `container_name` (plus Loki's automatic `service_name`).

**Where to look in Grafana.** The **FCG Logs** dashboard has a `service` variable
(`compose_service`) and an `orderId` text box:

| Panel | LogQL |
|---|---|
| Log volume by service | `sum by (compose_service) (count_over_time({platform="fcg", compose_service=~"$service"}[1m]))` |
| Trace an order across services | `{platform="fcg", compose_service=~"catalog-api\|payments-api\|notifications-function"} \|= "$orderId"` |
| Notification e-mails | `{compose_service="notifications-function"} \|~ "WELCOME EMAIL\|PURCHASE CONFIRMATION\|no confirmation e-mail"` |
| Warnings and errors | `{compose_service=~"users-api\|catalog-api\|payments-api\|notifications-function"} \|~ "\\[(WRN\|ERR)\\]\|warn:\|fail:\|Exception"` |
| Kong access log | `{compose_service="kong"} \|= "/api/"` |
| All logs for the selected services | `{platform="fcg", compose_service=~"$service"}` |

**Useful ad-hoc queries (Explore → Loki):**

```logql
{compose_service="users-api"}                                   # one service
{compose_service=~"users-api|catalog-api|payments-api"}         # the three APIs
{platform="fcg"} |= "5bd8f8ad-f95d-41f3-a3da-466f0ba3424f"      # everything about one OrderId (catalog -> payments -> function)
{compose_service="notifications-function"} |= "[WELCOME EMAIL]"
{compose_service="notifications-function"} |= "[PURCHASE CONFIRMATION]"
{compose_service="kong"} |= " 401 "                              # rejected at the edge
sum by (compose_service) (count_over_time({platform="fcg"}[5m]))
```

**Loki HTTP API (for scripts):**

```bash
curl -s http://localhost:3100/ready
curl -s http://localhost:3100/loki/api/v1/label/compose_service/values
curl -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={compose_service="notifications-function"} |= "[PURCHASE CONFIRMATION]"' --data-urlencode 'limit=20'
```

## Notifications Function in Compose

Since P3-M6 the **Notifications Function** (`fiap-cloud-games-notifications-function`) runs as
the compose service `notifications-function` (image built from the official Azure Functions
base, consumer group `notifications-function`, broker `kafka:9092`). It is the **main Phase 3
notification path**; the Phase 2 `notifications-api` is kept in the repository as history and
in `docker-compose.yml` only under the `phase2-legacy` profile (not started by default, so there
is a single notification consumer). `func start` on the host remains the development path —
do not run both against the same Kafka at the same time (same consumer group).

## Validating locally

```bash
docker compose up -d --build
curl -s http://localhost:3100/ready                                                   # ready
curl -s http://localhost:3100/loki/api/v1/label/compose_service/values                # users-api, catalog-api, ..., notifications-function
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c
curl -s -u admin:admin http://localhost:3000/api/datasources | grep -o '"name":"[A-Za-z]*"'   # Prometheus, Loki
curl -s -u admin:admin "http://localhost:3000/api/search?query=FCG" | grep -o '"title":"[^"]*"'
```

Run the demo flow through Kong (register, login, `GET /api/games` twice, acquire, query the
payment, a rejected purchase; pause ~1 s between calls to stay under the 5 req/s rate limit),
then open **FCG Logs**, paste the `orderId` into the text box and watch the order cross
CatalogAPI → PaymentsAPI → Notifications Function; the e-mail panel shows the
`[WELCOME EMAIL]` and `[PURCHASE CONFIRMATION]` lines. **FCG Overview** shows the counters
moving within one scrape interval.

## Out of scope (by design)

No OpenTelemetry, no tracing (Tempo), no Alertmanager, no exporters for PostgreSQL/Redis/MongoDB/Kafka,
no persistence for Prometheus or Loki, no Kubernetes manifests for the observability stack
yet. **Log collection on Kubernetes** (Alloy DaemonSet with RBAC) is deferred to P3-M7 or
documented as a future improvement if too heavy for the local delivery.
