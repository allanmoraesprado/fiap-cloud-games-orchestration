#!/usr/bin/env bash
# Applies the full system to local Kubernetes in dependency order.
# Assumes the four service repos are cloned as siblings of this repo.
set -euo pipefail
K="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$K/../.." && pwd)"

kubectl apply -f "$K/namespace.yaml"
kubectl apply -f "$K/shared-config.yaml" -f "$K/shared-secret.yaml"
kubectl apply -f "$K/postgres.yaml" -f "$K/kafka.yaml"
kubectl -n fcg rollout status deploy/postgres --timeout=180s
kubectl -n fcg rollout status deploy/kafka --timeout=180s
kubectl apply -f "$K/kafka-topics-job.yaml"
kubectl -n fcg wait --for=condition=complete job/kafka-topics --timeout=180s
kubectl apply -f "$ROOT/fiap-cloud-games-users-api/k8s"
kubectl apply -f "$ROOT/fiap-cloud-games-catalog-api/k8s"
kubectl apply -f "$ROOT/fiap-cloud-games-payments-api/k8s"
kubectl apply -f "$ROOT/fiap-cloud-games-notifications-api/k8s"
for d in users-api catalog-api payments-api notifications-api; do
  kubectl -n fcg rollout status deploy/"$d" --timeout=180s
done
kubectl get pods -n fcg
kubectl get svc -n fcg
