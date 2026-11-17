# Key Vault in RBAC mode: data-plane access is granted per secret through Azure role
# assignments (see identities.tf), never through access policies or shared keys.
resource "azurerm_key_vault" "main" {
  name                          = local.names.key_vault
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false # disposable environment: allow purge after destroy
  public_network_access_enabled = true  # AKS reaches the vault over its public endpoint (no private endpoint cost)
  tags                          = local.tags

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

# The operator running Terraform writes the secrets and can read them (e.g. the seeded admin
# password) with `az keyvault secret show`.
resource "azurerm_role_assignment" "operator_kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure RBAC propagation can take a minute; writing secrets earlier fails with 403.
resource "time_sleep" "kv_rbac_propagation" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.operator_kv_secrets_officer]
}

# ---------------------------------------------------------------------------------------
# Generated secrets. Values come from EPHEMERAL random passwords and are sent through the
# write-only `value_wo` argument: they exist only in Key Vault, never in the Terraform state
# or plan. Every derived value (connection strings) is composed in the same run, so they stay
# consistent; bump var.secrets_version to rotate all of them together.
# ---------------------------------------------------------------------------------------
ephemeral "random_password" "jwt_signing_key" {
  length  = 64
  special = false
}

ephemeral "random_password" "postgres" {
  length  = 32
  special = false
}

ephemeral "random_password" "mongo" {
  length  = 32
  special = false
}

ephemeral "random_password" "redis" {
  length  = 32
  special = false
}

ephemeral "random_password" "grafana" {
  length  = 24
  special = false
}

# Seeded UsersAPI administrator (letters, digits and a special character, as the API requires).
ephemeral "random_password" "admin_seed" {
  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*-_"
}

locals {
  redis_options = "abortConnect=false,connectTimeout=2000,syncTimeout=2000"

  generated_secrets = {
    "jwt-signing-key"                 = ephemeral.random_password.jwt_signing_key.result
    "postgres-admin-password"         = ephemeral.random_password.postgres.result
    "mongo-root-password"             = ephemeral.random_password.mongo.result
    "redis-password"                  = ephemeral.random_password.redis.result
    "grafana-admin-password"          = ephemeral.random_password.grafana.result
    "users-admin-seed-password"       = ephemeral.random_password.admin_seed.result
    "users-api-postgres-connection"   = "Host=postgres;Port=5432;Database=fcg_users;Username=fcg;Password=${ephemeral.random_password.postgres.result}"
    "catalog-api-postgres-connection" = "Host=postgres;Port=5432;Database=fcg_catalog;Username=fcg;Password=${ephemeral.random_password.postgres.result}"
    "catalog-api-redis-connection"    = "redis:6379,password=${ephemeral.random_password.redis.result},${local.redis_options}"
    "payments-api-mongo-connection"   = "mongodb://fcg:${ephemeral.random_password.mongo.result}@mongo:27017/?authSource=admin"
  }

  # Externally provided (Elastic Cloud). Written with their own version counter.
  external_secrets = {
    "catalog-elasticsearch-url"     = var.elasticsearch_url
    "catalog-elasticsearch-api-key" = var.elasticsearch_api_key
  }

  # Names only (non-sensitive) for for_each.
  generated_secret_names = toset([
    "jwt-signing-key", "postgres-admin-password", "mongo-root-password", "redis-password",
    "grafana-admin-password", "users-admin-seed-password", "users-api-postgres-connection",
    "catalog-api-postgres-connection", "catalog-api-redis-connection", "payments-api-mongo-connection",
  ])
  external_secret_names = toset(["catalog-elasticsearch-url", "catalog-elasticsearch-api-key"])
}

resource "azurerm_key_vault_secret" "generated" {
  for_each = local.generated_secret_names

  name             = each.key
  key_vault_id     = azurerm_key_vault.main.id
  value_wo         = local.generated_secrets[each.key]
  value_wo_version = var.secrets_version
  content_type     = "generated"
  tags             = local.tags

  depends_on = [time_sleep.kv_rbac_propagation]
}

resource "azurerm_key_vault_secret" "external" {
  for_each = local.external_secret_names

  name             = each.key
  key_vault_id     = azurerm_key_vault.main.id
  value_wo         = local.external_secrets[each.key]
  value_wo_version = var.elasticsearch_secret_version
  content_type     = "external"
  tags             = local.tags

  depends_on = [time_sleep.kv_rbac_propagation]
}
