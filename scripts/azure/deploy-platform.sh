#!/usr/bin/env bash
# Deploys the platform layer of the AKS environment (namespace, ServiceAccounts with Workload
# Identity, SecretProviderClasses, PostgreSQL, Kafka + topics, Redis, MongoDB, Kong, Prometheus,
# Loki, Alloy, Grafana). Application workloads are deployed by each service's GitHub Actions
# pipeline (push to main or a manual run).
#
# Prerequisites: `terraform apply` done in infra/terraform, `az login` as the operator (Azure
# Kubernetes Service RBAC Cluster Admin, granted by Terraform), kubectl + kubelogin installed.
# Usage:  bash scripts/azure/deploy-platform.sh            (renders, applies and waits)
#         bash scripts/azure/deploy-platform.sh --render-only
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

render_only=false
[[ "${1:-}" == "--render-only" ]] && render_only=true

log "Loading Terraform outputs"
load_tf_outputs
echo "RG=$RESOURCE_GROUP AKS=$AKS_NAME KV=$KEYVAULT_NAME ACR=$ACR_LOGIN_SERVER Kong=http://$KONG_FQDN"

log "Rendering k8s/azure -> .rendered/platform"
rm -rf "$RENDER_DIR/platform"
render "$ORCH_DIR/k8s/azure" "$RENDER_DIR/platform"
$render_only && { echo "Rendered only."; exit 0; }

log "Cluster credentials (Entra ID / kubelogin)"
aks_credentials
kubectl get nodes -o wide

apply_platform "$RENDER_DIR/platform"

log "Platform ready"
kubectl -n fcg get pods,svc,pvc
echo
echo "Public gateway: http://$KONG_FQDN  (DNS may take a minute after the LoadBalancer gets its IP)"
echo "Next: bash scripts/azure/github-variables.sh, then deploy the services (push to main or Run workflow in each service repository)."
