# Non-sensitive identifiers consumed by scripts/azure-*.ps1 (manifest rendering) and by the
# GitHub repository variables. No secret value is ever output.
output "subscription_id" {
  value = var.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "location" {
  value = azurerm_resource_group.main.location
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "node_resource_group" {
  value = azurerm_kubernetes_cluster.main.node_resource_group
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "namespace" {
  value = var.namespace
}

output "workload_identity_client_ids" {
  description = "Client id per workload ServiceAccount (annotation azure.workload.identity/client-id)."
  value       = { for k, id in azurerm_user_assigned_identity.workload : k => id.client_id }
}

output "github_deploy_client_id" {
  description = "AZURE_CLIENT_ID for the GitHub Actions OIDC login."
  value       = azurerm_user_assigned_identity.github.client_id
}

output "kong_dns_label" {
  description = "Azure DNS label of the Kong LoadBalancer: <label>.<location>.cloudapp.azure.com"
  value       = "${local.prefix}-${local.suffix}"
}
