#!/usr/bin/env bash
# Read-only checks before `terraform apply` (creates nothing, costs nothing):
#  - Azure CLI session and subscription state (must be Enabled)
#  - operator permissions (Owner or User Access Administrator needed for role assignments)
#  - resource providers registered
#  - regional vCPU quota for the chosen VM family
#  - required local tools
# Usage: bash scripts/azure/preflight.sh <subscription-id> [location] [vm-size]
set -uo pipefail
SUB="${1:?subscription id required}"; LOC="${2:-eastus2}"; VM="${3:-Standard_D4as_v5}"
fail=0
ok()   { printf '  OK    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
warn() { printf '  WARN  %s\n' "$*"; }

echo "== Tools"
for t in az terraform kubectl kubelogin envsubst node; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else bad "$t not found"; fi
done

echo "== Subscription"
state="$(az account show --subscription "$SUB" --query state -o tsv 2>/dev/null)"
if [[ "$state" == "Enabled" ]]; then ok "subscription $SUB is Enabled"; else bad "subscription state is '${state:-unknown}' (must be Enabled; check billing in the Azure portal)"; fi
if az group list --subscription "$SUB" --query "length(@)" -o tsv >/dev/null 2>&1; then ok "ARM reachable"; else bad "ARM calls fail for this subscription"; fi

echo "== Operator role assignments (subscription scope)"
me="$(az ad signed-in-user show --query id -o tsv 2>/dev/null)"
roles="$(az role assignment list --assignee "$me" --scope "/subscriptions/$SUB" --include-inherited --query "[].roleDefinitionName" -o tsv 2>/dev/null | sort -u | tr '\n' ',')"
echo "  roles: ${roles:-none}"
if [[ "$roles" == *"Owner"* || "$roles" == *"User Access Administrator"* ]]; then ok "can create role assignments"; else bad "Owner or User Access Administrator required for role assignments"; fi

echo "== Resource providers"
for p in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.Network Microsoft.Compute Microsoft.Consumption; do
  s="$(az provider show -n "$p" --subscription "$SUB" --query registrationState -o tsv 2>/dev/null)"
  if [[ "$s" == "Registered" ]]; then ok "$p"; else warn "$p is '${s:-unknown}' -> az provider register -n $p --subscription $SUB"; fi
done

echo "== vCPU quota in $LOC for $VM"
family="$(az vm list-skus -l "$LOC" --size "$VM" --subscription "$SUB" --query "[0].family" -o tsv 2>/dev/null)"
if [[ -z "$family" ]]; then bad "VM size $VM not offered in $LOC for this subscription"; else
  az vm list-usage -l "$LOC" --subscription "$SUB" -o tsv --query "[?name.value=='$family' || name.value=='cores'].[name.value,currentValue,limit]" 2>/dev/null \
    | while read -r name cur lim; do echo "  $name: $cur used of $lim"; done
fi

echo
if [[ $fail -eq 0 ]]; then echo "Preflight OK. Review docs/phase4/COSTS.md, then: terraform -chdir=infra/terraform plan -out tfplan"; else echo "Preflight FAILED - fix the items above before provisioning."; fi
exit $fail
