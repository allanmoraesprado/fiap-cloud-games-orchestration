# GitHub Actions -> Azure without stored credentials (OIDC). The deploy identity trusts only
# workflow runs on the `main` branch of the listed repositories; pull requests (subject
# repo:<owner>/<repo>:pull_request) cannot obtain a token.
resource "azurerm_user_assigned_identity" "github" {
  name                = local.names.github
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = toset(var.github_deploy_repositories)

  name                      = "gh-${each.key}-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_owner}/${each.key}:ref:refs/heads/main"
  audience                  = ["api://AzureADTokenExchange"]
}

# Push images to the private registry.
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# `az acr login --name <registry>` resolves the registry through ARM (registries/read), which
# AcrPush does not include; Reader on the registry alone keeps it read-only.
resource "azurerm_role_assignment" "github_acr_reader" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# Fetch the (Entra ID) kubeconfig of the cluster...
resource "azurerm_role_assignment" "github_aks_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# ...and manage workloads only inside the application namespace (no cluster-wide rights,
# no RBAC objects).
resource "azurerm_role_assignment" "github_aks_namespace_writer" {
  scope                = "${azurerm_kubernetes_cluster.main.id}/namespaces/${var.namespace}"
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}
