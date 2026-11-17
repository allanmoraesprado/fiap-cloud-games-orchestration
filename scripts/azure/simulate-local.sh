#!/usr/bin/env bash
# Local rehearsal of the AKS manifests on Docker Desktop Kubernetes, in an isolated namespace
# (fcg-sim). Exercises exactly the k8s/azure files (and the services' k8s/azure folders when
# `--apps` is given) with only the Azure-specific pieces swapped:
#   - Key Vault CSI volume  -> a Kubernetes Secret with the same file names (dev values)
#   - managed-csi disks     -> the local default StorageClass
#   - Kong LoadBalancer     -> NodePort 30180 (http://localhost:30180)
#   - ACR images            -> local images tagged fcg-<service>:sim (build them first)
# Everything else (file-based secrets, *_FILE variables, Kong config rendering, Redis auth,
# KeyPerFile configuration, Prometheus pod discovery, Alloy -> Loki, probes, rolling updates)
# runs as it would on AKS. Nothing touches Azure.
#
# Usage: bash scripts/azure/simulate-local.sh up [--apps] | apps | down
set -euo pipefail
export NS="fcg-sim"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ctx="$(kubectl config current-context)"
[[ "$ctx" == "${SIM_CONTEXT:-docker-desktop}" ]] || die "refusing to run against context '$ctx' (expected docker-desktop)"

SIM="$RENDER_DIR/sim"
SECRETS_FILE="$SIM/dev-secrets.env"   # generated once, git-ignored (.rendered/)

fake_ids() {
  local fake="00000000-0000-0000-0000-00000000000"
  export AZURE_TENANT_ID="${fake}0" KEYVAULT_NAME="kv-sim" KONG_DNS_LABEL="fcg-sim"
  export ACR_LOGIN_SERVER="sim.local" IMAGE_TAG="${IMAGE_TAG:-sim}"
  export USERS_API_CLIENT_ID="${fake}1" CATALOG_API_CLIENT_ID="${fake}2" PAYMENTS_API_CLIENT_ID="${fake}3" KONG_CLIENT_ID="${fake}4"
  export POSTGRES_CLIENT_ID="${fake}5" MONGO_CLIENT_ID="${fake}6" REDIS_CLIENT_ID="${fake}7" GRAFANA_CLIENT_ID="${fake}8"
}

# Rewrites rendered AKS manifests for the local cluster (see header).
to_local() { # to_local <in dir> <out dir>
  node - "$1" "$2" <<'JS'
const fs = require("fs"), path = require("path");
const [inDir, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
for (const f of fs.readdirSync(inDir).filter(f => f.endsWith(".yaml"))) {
  if (f === "03-secret-provider-classes.yaml") continue;          // CRD not installed locally
  let s = fs.readFileSync(path.join(inDir, f), "utf8").split("\r\n").join("\n");
  s = s.replace(/^(\s*namespace:) fcg$/gm, "$1 fcg-sim").replace(/^(  name:) fcg$/m, "$1 fcg-sim");
  s = s.replace(/csi:\n(\s+)driver: secrets-store\.csi\.k8s\.io\n\s+readOnly: true\n\s+volumeAttributes:\n\s+secretProviderClass: ([a-z-]+)/g,
                (_, ind, spc) => `secret:\n${ind}secretName: ${spc}`);
  s = s.replace(/storageClassName: managed-csi/g, "storageClassName: hostpath");
  s = s.replace(/type: LoadBalancer\n  externalTrafficPolicy: Local/, "type: NodePort");
  s = s.replace(/(name: http\n\s+port: 80\n\s+targetPort: 8000)/, "$1\n      nodePort: 30180");
  s = s.replace(/image: sim\.local\/(fcg-[a-z-]+):[^\s]+/g, "image: $1:sim");   // manifests already use IfNotPresent
  if (/secrets-store\.csi/.test(s)) throw new Error(`CSI volume left in ${f}`);
  fs.writeFileSync(path.join(outDir, f), s);
}
JS
}

gen_secrets() {
  [[ -f "$SECRETS_FILE" ]] && return
  mkdir -p "$SIM"
  rnd() { node -e "process.stdout.write(require('crypto').randomBytes($1).toString('hex'))"; }
  {
    echo "JWT=$(rnd 32)"; echo "PG=$(rnd 16)"; echo "MONGO=$(rnd 16)"; echo "REDIS=$(rnd 16)"
    echo "GRAFANA=$(rnd 12)"; echo "ADMIN=Sim-$(rnd 6)#1"
  } > "$SECRETS_FILE"
}

apply_secrets() {
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
  local redis_opts="abortConnect=false,connectTimeout=2000,syncTimeout=2000" k="kubectl -n $NS"
  sec() { local n="$1"; shift; $k create secret generic "$n" "$@" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; echo "  secret/$n"; }
  sec postgres-secrets --from-literal=postgres-admin-password="$PG"
  sec mongo-secrets --from-literal=mongo-root-password="$MONGO"
  sec redis-secrets --from-literal=redis-password="$REDIS"
  sec grafana-secrets --from-literal=grafana-admin-password="$GRAFANA"
  sec kong-secrets --from-literal=jwt-signing-key="$JWT"
  sec users-api-secrets --from-literal=Jwt__SecretKey="$JWT" \
    --from-literal=ConnectionStrings__Postgres="Host=postgres;Port=5432;Database=fcg_users;Username=fcg;Password=$PG" \
    --from-literal=Seed__AdminPassword="$ADMIN"
  sec catalog-api-secrets --from-literal=Jwt__SecretKey="$JWT" \
    --from-literal=ConnectionStrings__Postgres="Host=postgres;Port=5432;Database=fcg_catalog;Username=fcg;Password=$PG" \
    --from-literal=Redis__ConnectionString="redis:6379,password=$REDIS,$redis_opts" \
    --from-literal=Elasticsearch__Url="http://elasticsearch:9200" --from-literal=Elasticsearch__ApiKey="not-configured"
  sec payments-api-secrets --from-literal=Jwt__SecretKey="$JWT" \
    --from-literal=Mongo__ConnectionString="mongodb://fcg:$MONGO@mongo:27017/?authSource=admin"
}

up() {
  fake_ids
  rm -rf "$SIM/raw" "$SIM/platform" "$SIM/observability"
  render "$ORCH_DIR/k8s/azure" "$SIM/raw/platform"
  to_local "$SIM/raw/platform" "$SIM/platform"
  mkdir -p "$SIM/observability"; cp -r "$ORCH_DIR/observability/." "$SIM/observability/"
  sed -i 's/names: \[fcg\]/names: [fcg-sim]/' "$SIM/observability/prometheus/prometheus-aks.yml"
  sed -i 's/names = \["fcg"\]/names = ["fcg-sim"]/' "$SIM/observability/alloy/config-aks.alloy"
  export OBS_DIR="$SIM/observability"
  gen_secrets
  kubectl apply -f "$SIM/platform/00-namespace.yaml"
  log "dev secrets (stand-in for the Key Vault CSI mount)"
  apply_secrets
  # Local Elasticsearch stands in for Elastic Cloud.
  sed 's/^\(\s*namespace:\) fcg$/\1 fcg-sim/' "$ORCH_DIR/k8s/elasticsearch.yaml" | kubectl apply -f -
  apply_platform "$SIM/platform"
}

apps() {
  fake_ids
  local svc
  for svc in users-api catalog-api payments-api notifications-function; do
    local dir="$ORCH_DIR/../fiap-cloud-games-$svc/k8s/azure"
    [[ -d "$dir" ]] || { echo "skip $svc (no k8s/azure)"; continue; }
    rm -rf "$SIM/raw/$svc" "$SIM/$svc"
    render "$dir" "$SIM/raw/$svc"
    to_local "$SIM/raw/$svc" "$SIM/$svc"
    log "apply $svc"
    kubectl apply -f "$SIM/$svc"
  done
  for svc in users-api catalog-api payments-api notifications-function; do
    kubectl -n "$NS" rollout status deploy/$svc --timeout=300s || true
  done
  kubectl -n "$NS" get pods -o wide
}

case "${1:-}" in
  up)   up; [[ "${2:-}" == "--apps" ]] && apps; kubectl -n "$NS" get pods,svc,pvc ;;
  apps) apps ;;
  down) kubectl delete namespace "$NS" --ignore-not-found ;;
  *)    echo "usage: $0 up [--apps] | apps | down"; exit 2 ;;
esac
