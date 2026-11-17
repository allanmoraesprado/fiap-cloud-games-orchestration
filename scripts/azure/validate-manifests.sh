#!/usr/bin/env bash
# Offline validation of the AKS manifests (no Azure access needed): renders every k8s/azure
# file (and, when present, the services' k8s/azure folders next to this repo) with fake
# identifiers, then validates them against the Kubernetes JSON schemas (kubeconform), including
# the SecretProviderClass CRD. Used locally and by the orchestration CI workflow.
# Usage: bash scripts/azure/validate-manifests.sh   (KUBECONFORM=/path/to/kubeconform optional)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake="00000000-0000-0000-0000-00000000000"
export AZURE_TENANT_ID="${fake}0" KEYVAULT_NAME="kv-fcg-demo-xxxxx" KONG_DNS_LABEL="fcg-demo-xxxxx"
export ACR_LOGIN_SERVER="acrfcgdemoxxxxx.azurecr.io" IMAGE_TAG="0123456789abcdef0123456789abcdef01234567"
export USERS_API_CLIENT_ID="${fake}1" CATALOG_API_CLIENT_ID="${fake}2" PAYMENTS_API_CLIENT_ID="${fake}3" KONG_CLIENT_ID="${fake}4"
export POSTGRES_CLIENT_ID="${fake}5" MONGO_CLIENT_ID="${fake}6" REDIS_CLIENT_ID="${fake}7" GRAFANA_CLIENT_ID="${fake}8"

out="$RENDER_DIR/validate"
rm -rf "$out"
render "$ORCH_DIR/k8s/azure" "$out/platform"
for svc in users-api catalog-api payments-api notifications-function; do
  dir="$ORCH_DIR/../fiap-cloud-games-$svc/k8s/azure"
  [[ -d "$dir" ]] && render "$dir" "$out/$svc"
done

KC="${KUBECONFORM:-kubeconform}"
"$KC" -strict -summary -kubernetes-version "${K8S_VERSION:-1.33.0}" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$out"
