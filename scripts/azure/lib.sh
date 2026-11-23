#!/usr/bin/env bash
# Shared helpers for the Azure scripts. Source it: `source scripts/azure/lib.sh`.
# Works in Git Bash (Windows) and Linux (GitHub Actions). Requires: az, terraform, jq or node,
# envsubst (gettext), kubectl + kubelogin for cluster access.
set -euo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ORCH_DIR/infra/terraform"
RENDER_DIR="$ORCH_DIR/.rendered"
NS="${NS:-fcg}"                               # target namespace (fcg-sim for the local rehearsal)
OBS_DIR="${OBS_DIR:-$ORCH_DIR/observability}"  # observability config files used for ConfigMaps

# Only these placeholders are substituted in manifests. Anything else that looks like a shell
# variable (e.g. "$(cat ...)" or "${key}" inside container scripts) is left untouched.
RENDER_VARS='${AZURE_TENANT_ID} ${KEYVAULT_NAME} ${KONG_DNS_LABEL} ${ACR_LOGIN_SERVER} ${IMAGE_TAG}
${USERS_API_CLIENT_ID} ${CATALOG_API_CLIENT_ID} ${PAYMENTS_API_CLIENT_ID} ${KONG_CLIENT_ID}
${POSTGRES_CLIENT_ID} ${MONGO_CLIENT_ID} ${REDIS_CLIENT_ID} ${GRAFANA_CLIENT_ID}'

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

json_get() { # json_get <json> <js expression on `o`>
  node -e 'const o=JSON.parse(process.argv[1]); const v=('"$2"'); process.stdout.write(v==null?"":String(v));' "$1"
}

# Exports the non-sensitive identifiers produced by Terraform as environment variables.
load_tf_outputs() {
  local tf="${TERRAFORM:-terraform}" out
  out="$("$tf" -chdir="$TF_DIR" output -json)" || die "terraform output failed (run terraform apply first)"
  export AZURE_SUBSCRIPTION_ID="$(json_get "$out" 'o.subscription_id.value')"
  export AZURE_TENANT_ID="$(json_get "$out" 'o.tenant_id.value')"
  export AZURE_LOCATION="$(json_get "$out" 'o.location.value')"
  export RESOURCE_GROUP="$(json_get "$out" 'o.resource_group.value')"
  export NODE_RESOURCE_GROUP="$(json_get "$out" 'o.node_resource_group.value')"
  export AKS_NAME="$(json_get "$out" 'o.aks_name.value')"
  export ACR_NAME="$(json_get "$out" 'o.acr_name.value')"
  export ACR_LOGIN_SERVER="$(json_get "$out" 'o.acr_login_server.value')"
  export KEYVAULT_NAME="$(json_get "$out" 'o.key_vault_name.value')"
  export KONG_DNS_LABEL="$(json_get "$out" 'o.kong_dns_label.value')"
  export GITHUB_DEPLOY_CLIENT_ID="$(json_get "$out" 'o.github_deploy_client_id.value')"
  local ids; ids="$(json_get "$out" 'JSON.stringify(o.workload_identity_client_ids.value)')"
  export USERS_API_CLIENT_ID="$(json_get "$ids" 'o["users-api"]')"
  export CATALOG_API_CLIENT_ID="$(json_get "$ids" 'o["catalog-api"]')"
  export PAYMENTS_API_CLIENT_ID="$(json_get "$ids" 'o["payments-api"]')"
  export KONG_CLIENT_ID="$(json_get "$ids" 'o["kong"]')"
  export POSTGRES_CLIENT_ID="$(json_get "$ids" 'o["postgres"]')"
  export MONGO_CLIENT_ID="$(json_get "$ids" 'o["mongo"]')"
  export REDIS_CLIENT_ID="$(json_get "$ids" 'o["redis"]')"
  export GRAFANA_CLIENT_ID="$(json_get "$ids" 'o["grafana"]')"
  export KONG_FQDN="${KONG_DNS_LABEL}.${AZURE_LOCATION}.cloudapp.azure.com"
}

# render <source dir or file> <output dir>: substitutes RENDER_VARS and fails on leftovers.
render() {
  local src="$1" out="$2" f
  mkdir -p "$out"
  for f in $( [ -d "$src" ] && ls "$src"/*.yaml || echo "$src" ); do
    envsubst "$RENDER_VARS" < "$f" > "$out/$(basename "$f")"
  done
  if grep -nE '\$\{(AZURE_TENANT_ID|KEYVAULT_NAME|KONG_DNS_LABEL|ACR_LOGIN_SERVER|IMAGE_TAG|[A-Z_]+_CLIENT_ID)\}' "$out"/*.yaml; then
    die "unrendered placeholders left in $out"
  fi
  if grep -nE '(client-id|clientID|tenantId|tenant-id|keyvaultName): ""' "$out"/*.yaml; then
    die "empty identity/vault values in $out (missing environment variables?)"
  fi
}

# Points kubectl at the cluster with Entra ID auth (local accounts are disabled). Honors
# KUBECONFIG (a single file), so the cluster can be kept out of the default kubeconfig:
#   export KUBECONFIG="$HOME/.kube/fcg-aks-demo"
aks_credentials() {
  local file="${KUBECONFIG:-$HOME/.kube/config}"
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --file "$file" --overwrite-existing --only-show-errors
  kubelogin convert-kubeconfig -l azurecli --kubeconfig "$file"
}

# configmap_from_files <name> <key=path>...: idempotent create-or-update.
configmap_from_files() {
  local name="$1"; shift
  local args=() kv
  for kv in "$@"; do args+=("--from-file=$kv"); done
  kubectl -n "$NS" create configmap "$name" "${args[@]}" --dry-run=client -o yaml | kubectl apply -f -
}

# apply_platform <rendered dir>: applies the platform layer in dependency order and waits.
apply_platform() {
  local P="$1" O="$OBS_DIR" k="kubectl -n $NS"
  log "1) namespace, shared config, ServiceAccounts, SecretProviderClasses"
  kubectl apply -f "$P/00-namespace.yaml"
  kubectl apply -f "$P/01-shared-config.yaml" -f "$P/02-service-accounts.yaml"
  [[ -f "$P/03-secret-provider-classes.yaml" ]] && kubectl apply -f "$P/03-secret-provider-classes.yaml"

  log "2) file-based ConfigMaps (single source of truth shared with Compose)"
  configmap_from_files kong-declarative-template "kong.yml=$ORCH_DIR/gateway/kong.yml"
  configmap_from_files prometheus-config "prometheus.yml=$O/prometheus/prometheus-aks.yml"
  configmap_from_files loki-config "loki.yml=$O/loki/loki.yml"
  configmap_from_files alloy-config "config.alloy=$O/alloy/config-aks.alloy"
  configmap_from_files grafana-datasources "prometheus.yml=$O/grafana/provisioning/datasources/prometheus.yml" "loki.yml=$O/grafana/provisioning/datasources/loki.yml"
  configmap_from_files grafana-dashboard-provider "dashboards.yml=$O/grafana/provisioning/dashboards/dashboards.yml"
  configmap_from_files grafana-dashboards "fcg-overview.json=$O/grafana/dashboards/fcg-overview.json" "fcg-logs.json=$O/grafana/dashboards/fcg-logs.json"

  log "3) data services"
  kubectl apply -f "$P/10-postgres.yaml" -f "$P/11-kafka.yaml" -f "$P/13-redis.yaml" -f "$P/14-mongo.yaml"
  $k rollout status statefulset/postgres --timeout=300s
  $k rollout status statefulset/kafka --timeout=300s
  $k rollout status deploy/redis --timeout=180s
  $k rollout status statefulset/mongo --timeout=300s

  log "4) Kafka topics"
  $k delete job kafka-topics --ignore-not-found
  kubectl apply -f "$P/12-kafka-topics-job.yaml"
  $k wait --for=condition=complete job/kafka-topics --timeout=300s

  log "5) Kong (public entry point)"
  kubectl apply -f "$P/20-kong.yaml"
  $k rollout restart deploy/kong >/dev/null   # re-render kong.yml from the current template/secret
  $k rollout status deploy/kong --timeout=180s

  log "6) observability"
  kubectl apply -f "$P/30-prometheus.yaml" -f "$P/31-loki.yaml" -f "$P/32-alloy.yaml" -f "$P/33-grafana.yaml"
  local d; for d in prometheus loki alloy grafana; do $k rollout status deploy/$d --timeout=240s; done
}
