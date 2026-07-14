# Applies the full system to local Kubernetes in dependency order.
# Assumes the four service repos are cloned as siblings of this repo.
#
# We do NOT set $ErrorActionPreference='Stop' (kubectl can write warnings to
# stderr, which would abort the script under PowerShell). Critical waits use
# `kubectl rollout status` / `kubectl wait`, whose exit codes signal failure.
$k = $PSScriptRoot
$root = Split-Path (Split-Path $k)   # ...\Projects

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

Write-Host "5) microservices (from sibling repos)"
kubectl apply -f "$root\fiap-cloud-games-users-api\k8s"
kubectl apply -f "$root\fiap-cloud-games-catalog-api\k8s"
kubectl apply -f "$root\fiap-cloud-games-payments-api\k8s"
kubectl apply -f "$root\fiap-cloud-games-notifications-api\k8s"
foreach ($d in "users-api", "catalog-api", "payments-api", "notifications-api") {
  kubectl -n fcg rollout status deploy/$d --timeout=180s
}

Write-Host "Done. Current state:"
kubectl get pods -n fcg
kubectl get svc -n fcg
