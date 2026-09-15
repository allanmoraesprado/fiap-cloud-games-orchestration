# Kubernetes (local) — FIAP Cloud Games (Phase 3)

The whole Phase 3 platform runs on **local Kubernetes** (Docker Desktop) with **pure
manifests**: Deployments, Services, ConfigMaps and one Secret in the `fcg` namespace, one
replica each, ephemeral storage. No Helm, no Ingress, no service mesh, no cloud resources.

The layout stays **hybrid**: each application repo owns its `k8s/` (ConfigMap + Deployment [+
Service]); this repo owns the shared infrastructure, the gateway, the observability stack and the
build/apply scripts.

## What runs

| Component | Manifest | Kind | Access |
|---|---|---|---|
| PostgreSQL 16 | `k8s/postgres.yaml` | Deployment + Service, emptyDir, init ConfigMap | `postgres:5432` (in-cluster) |
| Kafka 3.9 (KRaft) | `k8s/kafka.yaml` | Deployment + Service | `kafka:9092` (in-cluster only) |
| Topics | `k8s/kafka-topics-job.yaml` | Job | — |
| Redis 7 | `k8s/redis.yaml` | Deployment + Service | `redis:6379` |
| MongoDB 7 | `k8s/mongo.yaml` | Deployment + Service, emptyDir | `mongo:27017` |
| UsersAPI / CatalogAPI / PaymentsAPI | `<repo>/k8s/` | ConfigMap + Deployment + Service | `users-api:8080`, `catalog-api:8080`, `payments-api:8080` |
| Notifications Function | `fiap-cloud-games-notifications-function/k8s/` | ConfigMap + Deployment (no Service) | `kubectl logs` |
| Kong 3.9 (DB-less) | `k8s/kong.yaml` | Deployment + `kong` ClusterIP (8000/8001/8100) + `kong-nodeport` | **http://localhost:30080** |
| Prometheus | `k8s/prometheus.yaml` | Deployment + NodePort | http://localhost:30090 |
| Grafana 12 | `k8s/grafana.yaml` | Deployment + NodePort | http://localhost:30300 (`admin` / `admin`) |

The Phase 2 `notifications-api` is **not** part of the Kubernetes flow (its `k8s/` folder is kept
in its repository as history).

## Single source of truth for file-based configuration

`apply-all` builds these ConfigMaps from the files already used by Docker Compose, so the gateway
and the observability configuration are never duplicated:

| ConfigMap | Source file | Mounted at |
|---|---|---|
| `kong-declarative` | `gateway/kong.yml` | `/kong/declarative/kong.yml` |
| `prometheus-config` | `observability/prometheus/prometheus.yml` | `/etc/prometheus/prometheus.yml` |
| `grafana-datasources` | `observability/grafana/provisioning/datasources/prometheus.yml` | `/etc/grafana/provisioning/datasources/` |
| `grafana-dashboard-provider` | `observability/grafana/provisioning/dashboards/dashboards.yml` | `/etc/grafana/provisioning/dashboards/` |
| `grafana-dashboards` | `observability/grafana/dashboards/fcg-overview.json` | `/var/lib/grafana/dashboards/` |

This works because the Kubernetes Service names equal the Compose service names
(`users-api`, `catalog-api`, `payments-api`, `kong`, `redis`, `mongo`, `kafka`, `postgres`).
After changing one of those files, re-run the apply script and restart the consumer:
`kubectl -n fcg rollout restart deploy/kong deploy/prometheus deploy/grafana`.

## Shared ConfigMap and Secret

| Object | Keys |
|---|---|
| `fcg-config` (ConfigMap) | `Jwt__Issuer`, `Jwt__Audience`, `Kafka__BootstrapServers=kafka:9092` |
| `fcg-secret` (Secret, **placeholders**) | `Jwt__SecretKey`, `Postgres__Password`, `Mongo__Password`, `Grafana__AdminPassword` |
| `catalog-api-config` | Kafka topics/group + `Redis__Enabled`, `Redis__ConnectionString=redis:6379,...`, `Redis__DefaultTtlSeconds`, `Redis__ExposeOutcomeHeader` |
| `payments-api-config` | Kafka topics/group, `Payment__RejectAboveAmount`, `Mongo__DatabaseName`, `Mongo__PaymentsCollectionName` (connection string composed in the Deployment from the Secret) |
| `notifications-function-config` | `Kafka__UserCreatedTopic`, `Kafka__PaymentProcessedTopic`, `Kafka__ConsumerGroup=notifications-function`, `AzureWebJobsStorage` placeholder |

The JWT placeholder in `fcg-secret` is the same value embedded in `gateway/kong.yml`
(Kong OSS cannot read it from a vault): Kong validates the token at the edge and the services
validate it again.

## Build and apply

```powershell
# PowerShell (primary on Windows); shell equivalents: k8s/build-images.sh, k8s/apply-all.sh
.\k8s\build-images.ps1     # fcg-users-api, fcg-catalog-api, fcg-payments-api, fcg-notifications-function (:local)
.\k8s\apply-all.ps1        # namespace -> config/secret -> postgres+kafka -> topics -> redis+mongo -> APIs -> function -> kong -> prometheus -> grafana
```

Prerequisites: Docker Desktop with Kubernetes enabled, the service repos cloned as siblings,
and the Compose stack stopped (`docker compose down`) so host ports do not clash. To start from a
clean slate: `kubectl delete namespace fcg` (wait until it is gone), then apply again.

## Validate

```powershell
kubectl get pods,svc,configmap,secret -n fcg
# 12 workloads Running + kafka-topics Completed

# Kong is the entry point (JWT at the edge on the protected routes)
curl.exe -X POST http://localhost:30080/api/auth/register -H "Content-Type: application/json" -d '{"name":"Ana","email":"ana@fcg.com","password":"Ana@1234"}'
curl.exe -i http://localhost:30080/api/games                        # 401 from Kong
curl.exe -i http://localhost:30080/api/games -H "Authorization: Bearer <token>"   # 200 + X-FCG-Cache MISS, then HIT

# Redis / MongoDB / function evidence
kubectl -n fcg exec deploy/redis -- redis-cli KEYS 'fcg:catalog:*'
kubectl -n fcg exec deploy/mongo -- mongosh -u fcg -p fcg --authenticationDatabase admin fcg_payments --quiet --eval "db.payments.find().pretty()"
kubectl -n fcg logs deploy/notifications-function | Select-String "EMAIL|CONFIRMATION"

# Kafka consumer groups (payments-service, catalog-service, notifications-function -> LAG 0)
$KPOD = kubectl get pod -n fcg -l app=kafka -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups

# Observability
curl.exe -s http://localhost:30090/api/v1/targets     # users-api, catalog-api, payments-api, kong, prometheus -> up
# Grafana http://localhost:30300 -> Dashboards -> FCG -> FCG Overview

# Swagger (direct, development only): port-forward a Service
kubectl port-forward -n fcg svc/catalog-api 18082:8080     # http://localhost:18082/swagger
```

Tear down: `kubectl delete namespace fcg`.

## Local-only and placeholders

- Kafka PLAINTEXT with the in-cluster listener only; Postgres/Mongo on `emptyDir` (data is lost
  on pod restart; the APIs re-migrate/re-seed, PaymentsAPI recreates its index).
- Redis without auth or persistence; Mongo root user `fcg`/`fcg`; Grafana `admin`/`admin`;
  JWT key: the committed dev placeholder. All from `k8s/shared-secret.yaml` / ConfigMaps —
  **no real secret exists**; a production deployment would use a managed secret store.
- NodePorts (30080/30090/30300) instead of an Ingress; Kong Admin/Status APIs are ClusterIP only.
- Prometheus: 2-day retention on `emptyDir`.

## Logging decision on Kubernetes

Centralized logs (Loki + Alloy) are implemented and validated on **Docker Compose**.
On Kubernetes, collecting pod logs needs an Alloy **DaemonSet with RBAC** (ClusterRole to list
pods and read logs through the kubelet) plus a Loki Deployment; that is more infrastructure
than this local delivery needs, so it is **documented as a future improvement**. On the cluster,
use `kubectl logs` (e.g. `kubectl -n fcg logs deploy/notifications-function`); the Grafana on
Kubernetes therefore ships only the Prometheus datasource and the **FCG Overview** dashboard.
