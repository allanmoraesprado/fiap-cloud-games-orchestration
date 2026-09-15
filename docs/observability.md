# Observability (Prometheus + Grafana) — FIAP Cloud Games (Phase 3)

Phase 3 adds **metrics** to the platform: the three .NET APIs expose Prometheus metrics,
**Kong** already exposes its own (P3-M2), **Prometheus** scrapes all of them over the compose
network and **Grafana** is provisioned automatically with the datasource and the
**FCG Overview** dashboard. Everything lives under `observability/` in this repository.

> **Centralized logs (Grafana Loki + Alloy) are implemented in P3-M6**, on top of this
> Grafana. Distributed tracing is intentionally out of scope.

## How this satisfies the Phase 3 observability requirement

| Requirement | Where |
|---|---|
| Metrics per service | `/metrics` on UsersAPI, CatalogAPI and PaymentsAPI (`prometheus-net.AspNetCore`): default HTTP metrics + domain counters |
| Gateway metrics | Kong `prometheus` plugin on the Status API (`kong:8100/metrics`) |
| Collection | Prometheus with static targets (`observability/prometheus/prometheus.yml`), 5 s scrape interval |
| Visualization | Grafana, datasource + dashboard provisioned from files (`observability/grafana/`), no manual setup |
| Central platform | Grafana is the single pane: metrics now, logs (Loki) in P3-M6 |

## URLs and credentials (local/dev only)

| Component | URL | Notes |
|---|---|---|
| Prometheus | `http://localhost:9090` (`PROMETHEUS_HOST_PORT`) | Status → Targets shows the five jobs; PromQL in Graph |
| Grafana | `http://localhost:3000` (`GRAFANA_HOST_PORT`) | login `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` (defaults `admin` / `admin`, placeholders from `.env.example`) |
| Dashboard | Grafana → Dashboards → folder **FCG** → **FCG Overview** | uid `fcg-overview`, refresh 10 s, last 30 min |
| UsersAPI metrics | `http://localhost:8080/metrics` | direct port only |
| CatalogAPI metrics | `http://localhost:8082/metrics` | direct port only |
| PaymentsAPI metrics | `http://localhost:8083/metrics` | direct port only |
| Kong metrics | `http://127.0.0.1:8100/metrics` | Status API, localhost only |

`/metrics` is **not** routed by Kong: Prometheus scrapes the services by their compose DNS
names (`users-api:8080`, `catalog-api:8080`, `payments-api:8080`, `kong:8100`).

## Scraped targets

| Job | Target | Source |
|---|---|---|
| `users-api` | `users-api:8080/metrics` | prometheus-net |
| `catalog-api` | `catalog-api:8080/metrics` | prometheus-net |
| `payments-api` | `payments-api:8080/metrics` | prometheus-net |
| `kong` | `kong:8100/metrics` | Kong prometheus plugin (P3-M2) |
| `prometheus` | `localhost:9090` | self |

Retention 2 days, no persistent volume (metrics are a demo artefact and rebuild from zero),
no Alertmanager, no Kubernetes service discovery (later milestone).

## Metrics available

**Default (all three APIs, prometheus-net):** `http_requests_received_total{code,method,controller,action}`,
`http_request_duration_seconds` (histogram), `http_requests_in_progress`, plus .NET/process
metrics (`dotnet_*`, `process_*`).

**Custom counters** — labels are low-cardinality only (never user ids, e-mails, order or game ids):

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
| Kong | `kong_http_requests_total{service,route,code,source}`, `kong_request_latency_ms_*`, `kong_bandwidth_bytes`, `kong_upstream_target_health` | from the plugin; `source="kong"` marks responses generated at the edge (401/429) |

Prometheus adds `job` and `instance` to every series, which is how the dashboard splits by service.

## The FCG Overview dashboard

| Panel | Query idea |
|---|---|
| Request rate by service | `sum by (job) (rate(http_requests_received_total[1m]))` |
| HTTP responses by service and status | `sum by (job, code) (rate(http_requests_received_total[1m]))` |
| Latency p95 by service | `histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))` |
| Kong requests by route and status | `sum by (route, code) (rate(kong_http_requests_total[1m]))` |
| Cache outcomes / hit ratio / invalidations | `fcg_cache_requests_total`, `fcg_cache_invalidations_total` |
| Payment decisions / queries / history writes | `fcg_payments_*_total` |
| Registrations and logins, library grants | `fcg_users_*_total`, `fcg_catalog_library_grants_total` |
| Kafka events published / consumed | `fcg_events_published_total`, `fcg_events_consumed_total` |
| Kong rejected at the edge, scrape targets up | `kong_http_requests_total{source="kong"}`, `up` |

Stat panels use `increase(...[$__range])`, so they show totals for the selected time range.

## Validating locally

```bash
docker compose up -d --build
curl -s http://localhost:8082/metrics | grep -E "^fcg_|^http_requests_received_total" | head
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c     # 5 x "up"
curl -s -u admin:admin http://localhost:3000/api/datasources | grep -o '"name":"Prometheus"'
curl -s -u admin:admin "http://localhost:3000/api/search?query=FCG" | grep -o '"title":"FCG Overview"'
```

Then run the demo flow through Kong (register, login, `GET /api/games` twice, acquire, query the
payment, a rejected purchase — pause ~1 s between calls to stay under the 5 req/s rate limit) and
watch the counters move, e.g.:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(outcome)%20(fcg_cache_requests_total)'
curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(status)%20(fcg_payments_decisions_total)'
curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(job,topic)%20(fcg_events_published_total)'
curl -s 'http://localhost:9090/api/v1/query?query=sum%20by%20(route,code)%20(kong_http_requests_total)'
```

Or open the dashboard: the stats update within one scrape interval (5 s) plus the 10 s refresh.

## Out of scope (by design)

No OpenTelemetry, no tracing (Tempo), no Alertmanager, no exporters for PostgreSQL/Redis/MongoDB/Kafka,
no Prometheus persistence, no Kubernetes manifests yet (P3-M7). Loki + Alloy: **P3-M6**.
