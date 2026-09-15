# Applies the full Phase 3 system to local Kubernetes (Docker Desktop) in dependency order.
# Assumes the service repos are cloned as siblings of this repo.
#
# We do NOT set $ErrorActionPreference='Stop' (kubectl can write warnings to
# stderr, which would abort the script under PowerShell). Critical waits use
# `kubectl rollout status` / `kubectl wait`, whose exit codes signal failure.
#
# ConfigMaps built from files shared with Docker Compose (single source of truth):
#   kong-declarative           <- gateway/kong.yml
#   prometheus-config          <- observability/prometheus/prometheus.yml
#   grafana-datasources        <- observability/grafana/provisioning/datasources/prometheus.yml
#   grafana-dashboard-provider <- observability/grafana/provisioning/dashboards/dashboards.yml
#   grafana-dashboards         <- observability/grafana/dashboards/fcg-overview.json
# (delete + create keeps this idempotent without piping YAML through PowerShell.)
$k = $PSScriptRoot
$o = Split-Path $k                    # ...\fiap-cloud-games-orchestration
$root = Split-Path $o                 # ...\Projects

function New-ConfigMapFromFile($name, $key, $file) {
  kubectl -n fcg delete configmap $name --ignore-not-found | Out-Null
  kubectl -n fcg create configmap $name --from-file="$key=$file"
}

Write-Host "1) namespace"
kubectl apply -f "$k\namespace.yaml"

Write-Host "2) shared config + secret"
kubectl apply -f "$k\shared-config.yaml" -f "$k\shared-secret.yaml"

Write-Host "3) postgres + kafka"
kubectl apply -f "$k\postgres.yaml" -f "$k\kafka.yaml"
kubectl -n fcg rollout status deploy/postgres --timeout=180s
kubectl -n fcg rollout status deploy/kafka --timeout=180s

Write-Host "4) create topics (Job)"
kubectl apply -f "$k\kafka-topics-job.yaml"
kubectl -n fcg wait --for=condition=complete job/kafka-topics --timeout=180s

Write-Host "5) redis + mongo"
kubectl apply -f "$k\redis.yaml" -f "$k\mongo.yaml"
kubectl -n fcg rollout status deploy/redis --timeout=120s
kubectl -n fcg rollout status deploy/mongo --timeout=180s

Write-Host "6) APIs (from sibling repos)"
kubectl apply -f "$root\fiap-cloud-games-users-api\k8s"
kubectl apply -f "$root\fiap-cloud-games-catalog-api\k8s"
kubectl apply -f "$root\fiap-cloud-games-payments-api\k8s"
foreach ($d in "users-api", "catalog-api", "payments-api") {
  kubectl -n fcg rollout status deploy/$d --timeout=180s
}

Write-Host "7) notifications function (from sibling repo)"
kubectl apply -f "$root\fiap-cloud-games-notifications-function\k8s"
kubectl -n fcg rollout status deploy/notifications-function --timeout=180s

Write-Host "8) kong (declarative config from gateway/kong.yml)"
New-ConfigMapFromFile "kong-declarative" "kong.yml" "$o\gateway\kong.yml"
kubectl apply -f "$k\kong.yaml"
kubectl -n fcg rollout status deploy/kong --timeout=180s

Write-Host "9) prometheus (config from observability/prometheus/prometheus.yml)"
New-ConfigMapFromFile "prometheus-config" "prometheus.yml" "$o\observability\prometheus\prometheus.yml"
kubectl apply -f "$k\prometheus.yaml"
kubectl -n fcg rollout status deploy/prometheus --timeout=180s

Write-Host "10) grafana (provisioning from observability/grafana; Prometheus datasource + FCG Overview)"
New-ConfigMapFromFile "grafana-datasources" "prometheus.yml" "$o\observability\grafana\provisioning\datasources\prometheus.yml"
New-ConfigMapFromFile "grafana-dashboard-provider" "dashboards.yml" "$o\observability\grafana\provisioning\dashboards\dashboards.yml"
New-ConfigMapFromFile "grafana-dashboards" "fcg-overview.json" "$o\observability\grafana\dashboards\fcg-overview.json"
kubectl apply -f "$k\grafana.yaml"
kubectl -n fcg rollout status deploy/grafana --timeout=180s

Write-Host "Done. Current state:"
kubectl get pods -n fcg
kubectl get svc -n fcg
Write-Host ""
Write-Host "Kong (official entry point): http://localhost:30080   Prometheus: http://localhost:30090   Grafana: http://localhost:30300 (admin/admin)"
Write-Host "Changed a file-based ConfigMap? Re-run this script and then: kubectl -n fcg rollout restart deploy/kong deploy/prometheus deploy/grafana"
