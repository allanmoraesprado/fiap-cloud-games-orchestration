#!/usr/bin/env bash
# Configures the GitHub repository variables used by the CD job of every service (identifiers
# only - no secret: authentication is OIDC). With an authenticated GitHub CLI (`gh auth login`)
# the variables are set directly; otherwise the equivalent commands are printed.
# Usage: bash scripts/azure/github-variables.sh [--disable]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

owner="${GITHUB_OWNER:-allanmoraesprado}"
repos=(fiap-cloud-games-users-api fiap-cloud-games-catalog-api fiap-cloud-games-payments-api fiap-cloud-games-notifications-function)

if [[ "${1:-}" == "--disable" ]]; then
  vars=(AZURE_DEPLOY_ENABLED=false)
else
  load_tf_outputs
  vars=(
    "AZURE_CLIENT_ID=$GITHUB_DEPLOY_CLIENT_ID"
    "AZURE_TENANT_ID=$AZURE_TENANT_ID"
    "AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID"
    "ACR_NAME=$ACR_NAME"
    "AKS_NAME=$AKS_NAME"
    "AKS_RESOURCE_GROUP=$RESOURCE_GROUP"
    "GATEWAY_URL=http://$KONG_FQDN"
    "AZURE_DEPLOY_ENABLED=true"
  )
fi

use_gh=false
command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && use_gh=true

for repo in "${repos[@]}"; do
  for kv in "${vars[@]}"; do
    name="${kv%%=*}"; value="${kv#*=}"
    if $use_gh; then
      gh variable set "$name" --repo "$owner/$repo" --body "$value"
    else
      echo "gh variable set $name --repo $owner/$repo --body \"$value\""
    fi
  done
done
$use_gh && echo "Variables set." || echo "(GitHub CLI not authenticated: run the commands above, or set them in Settings > Secrets and variables > Actions > Variables)"
