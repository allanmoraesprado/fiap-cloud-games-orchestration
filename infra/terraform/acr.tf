# Private registry: no admin user, no anonymous pull. AKS pulls with its kubelet identity
# (AcrPull); GitHub Actions pushes with the OIDC deploy identity (AcrPush, see github.tf).
resource "azurerm_container_registry" "main" {
  name                   = local.names.acr
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  sku                    = "Basic"
  admin_enabled          = false
  anonymous_pull_enabled = false
  tags                   = local.tags
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
