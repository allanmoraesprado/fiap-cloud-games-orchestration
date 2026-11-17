# AKS Workload Identity: one user-assigned managed identity per workload, trusted only for
# that workload's ServiceAccount (system:serviceaccount:<namespace>:<name>) through the
# cluster's OIDC issuer. Each identity may read ONLY the Key Vault secrets it needs
# (role assignment scoped to the individual secret).
locals {
  workload_secrets = {
    "users-api"    = ["jwt-signing-key", "users-api-postgres-connection", "users-admin-seed-password"]
    "catalog-api"  = ["jwt-signing-key", "catalog-api-postgres-connection", "catalog-api-redis-connection", "catalog-elasticsearch-url", "catalog-elasticsearch-api-key"]
    "payments-api" = ["jwt-signing-key", "payments-api-mongo-connection"]
    "kong"         = ["jwt-signing-key"]
    "postgres"     = ["postgres-admin-password"]
    "mongo"        = ["mongo-root-password"]
    "redis"        = ["redis-password"]
    "grafana"      = ["grafana-admin-password"]
  }

  workload_secret_pairs = merge([
    for workload, secrets in local.workload_secrets : {
      for secret in secrets : "${workload}/${secret}" => { workload = workload, secret = secret }
    }
  ]...)

  all_secret_ids = merge(
    { for k, s in azurerm_key_vault_secret.generated : k => s.resource_versionless_id },
    { for k, s in azurerm_key_vault_secret.external : k => s.resource_versionless_id },
  )
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.workload_secrets

  name                = "id-${local.prefix}-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each = local.workload_secrets

  name                      = "fc-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.key].id
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.namespace}:${each.key}"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "workload_secret_reader" {
  for_each = local.workload_secret_pairs

  scope                = local.all_secret_ids[each.value.secret]
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload[each.value.workload].principal_id
  principal_type       = "ServicePrincipal"
}
