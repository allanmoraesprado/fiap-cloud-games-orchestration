#!/usr/bin/env bash
# Destroys the whole Azure environment created by infra/terraform (AKS + node resource group,
# ACR with its images, Key Vault (soft-deleted), identities, VNet, budget). Elastic Cloud is an
# external service: delete its deployment in the Elastic console separately.
#
# Collect the evidence you need (screenshots, logs, docs/phase4/TEST-EVIDENCE.md) BEFORE running.
# Usage: bash scripts/azure/destroy.sh   (asks for confirmation; nothing is deleted otherwise)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_tf_outputs
cat <<EOF
This will permanently delete:
  resource group      $RESOURCE_GROUP   (and the AKS node group $NODE_RESOURCE_GROUP)
  AKS cluster         $AKS_NAME
  container registry  $ACR_NAME (all images)
  key vault           $KEYVAULT_NAME (soft-deleted for 7 days)
  subscription        $AZURE_SUBSCRIPTION_ID
EOF
read -r -p "Type the resource group name to confirm: " answer
[[ "$answer" == "$RESOURCE_GROUP" ]] || die "confirmation did not match; nothing deleted"

log "terraform destroy"
"${TERRAFORM:-terraform}" -chdir="$TF_DIR" destroy -auto-approve

log "Leftover check"
for rg in "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"; do
  if [[ "$(az group exists -n "$rg" --subscription "$AZURE_SUBSCRIPTION_ID")" == "true" ]]; then
    echo "  STILL EXISTS: $rg"
  else
    echo "  gone: $rg"
  fi
done
echo "  soft-deleted vaults: $(az keyvault list-deleted --subscription "$AZURE_SUBSCRIPTION_ID" --query "[?name=='$KEYVAULT_NAME'].name" -o tsv)"
echo "  (optional) purge now: az keyvault purge -n $KEYVAULT_NAME"
echo
echo "Remember: delete the Elastic Cloud deployment and remove the local Terraform state"
echo "(infra/terraform/terraform.tfstate*) once you no longer need it."
