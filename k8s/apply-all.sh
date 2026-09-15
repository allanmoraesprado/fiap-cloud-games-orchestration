#!/usr/bin/env bash
# Applies the full Phase 3 system to local Kubernetes in dependency order.
# Assumes the service repos are cloned as siblings of this repo (see apply-all.ps1 for notes).
set -euo pipefail
K="$(cd "$(dirname "$0")" && pwd)"
O="$(cd "$K/.." && pwd)"          # orchestration repo root
ROOT="$(cd "$O/.." && pwd)"       # parent of the repos

cm_from_file() {  # name key file
  kubectl -n fcg delete configmap "$1" --ignore-not-found >/dev/null
  kubectl -n fcg create configmap "$1" --from-file="$2=$3"
}

echo "1) namespace";            kubectl apply -f "$K/namespace.yaml"
echo "2) shared config+secret"; kubectl apply -f "$K/shared-config.yaml" -f "$K/shared-secret.yaml"
echo "3) postgres + kafka";     kubectl apply -f "$K/postgres.yaml" -f "$K/kafka.yaml"
kubectl -n fcg rollout status deploy/postgres --timeout=180s
kubectl -n fcg rollout status deploy/kafka --timeout=180s
echo "4) topics job";           kubectl apply -f "$K/kafka-topics-job.yaml"
kubectl -n fcg wait --for=condition=complete job/kafka-topics --timeout=180s
echo "5) redis + mongo";        kubectl apply -f "$K/redis.yaml" -f "$K/mongo.yaml"
kubectl -n fcg rollout status deploy/redis --timeout=120s
kubectl -n fcg rollout status deploy/mongo --timeout=180s
echo "6) APIs"
kubectl apply -f "$ROOT/fiap-cloud-games-users-api/k8s"
kubectl apply -f "$ROOT/fiap-cloud-games-catalog-api/k8s"
kubectl apply -f "$ROOT/fiap-cloud-games-payments-api/k8s"
for d in users-api catalog-api payments-api; do kubectl -n fcg rollout status deploy/"$d" --timeout=180s; done
echo "7) notifications function"
kubectl apply -f "$ROOT/fiap-cloud-games-notifications-function/k8s"
kubectl -n fcg rollout status deploy/notifications-function --timeout=180s
echo "8) kong"
cm_from_file kong-declarative kong.yml "$O/gateway/kong.yml"
kubectl apply -f "$K/kong.yaml"
kubectl -n fcg rollout status deploy/kong --timeout=180s
echo "9) prometheus"
cm_from_file prometheus-config prometheus.yml "$O/observability/prometheus/prometheus.yml"
kubectl apply -f "$K/prometheus.yaml"
kubectl -n fcg rollout status deploy/prometheus --timeout=180s
echo "10) grafana"
cm_from_file grafana-datasources prometheus.yml "$O/observability/grafana/provisioning/datasources/prometheus.yml"
cm_from_file grafana-dashboard-provider dashboards.yml "$O/observability/grafana/provisioning/dashboards/dashboards.yml"
cm_from_file grafana-dashboards fcg-overview.json "$O/observability/grafana/dashboards/fcg-overview.json"
kubectl apply -f "$K/grafana.yaml"
kubectl -n fcg rollout status deploy/grafana --timeout=180s
kubectl get pods -n fcg
kubectl get svc -n fcg
echo "Kong: http://localhost:30080   Prometheus: http://localhost:30090   Grafana: http://localhost:30300 (admin/admin)"
