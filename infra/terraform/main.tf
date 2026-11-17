provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    resource_group {
      # The environment is disposable: `terraform destroy` removes the group even if
      # Kubernetes created extra resources inside it.
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      # Keep soft-delete semantics on destroy (no purge): the vault name stays reserved for the
      # retention period, which costs nothing. Purge manually if the name must be reused.
      purge_soft_delete_on_destroy = false
    }
  }
}

data "azurerm_client_config" "current" {}

# Short random suffix for globally unique names (ACR, Key Vault).
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  prefix = "fcg-${var.environment}"
  suffix = random_string.suffix.result

  names = {
    resource_group = "rg-${local.prefix}"
    node_rg        = "rg-${local.prefix}-aks-nodes"
    vnet           = "vnet-${local.prefix}"
    aks_subnet     = "snet-${local.prefix}-aks"
    aks            = "aks-${local.prefix}"
    aks_identity   = "id-${local.prefix}-aks"
    acr            = "acr${replace(local.prefix, "-", "")}${local.suffix}"
    key_vault      = "kv-${local.prefix}-${local.suffix}"
    github         = "id-${local.prefix}-github-deploy"
    budget         = "budget-${local.prefix}"
  }

  tags = merge({
    project       = "fiap-cloud-games"
    phase         = "4"
    environment   = var.environment
    "managed-by"  = "terraform"
    "cost-policy" = "temporary-demo"
  }, var.tags)
}

resource "azurerm_resource_group" "main" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}
