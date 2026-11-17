# Dedicated VNet for the cluster nodes. Pods use Azure CNI Overlay (pod_cidr), so the node
# subnet stays small. Inbound traffic reaches the cluster only through the Azure Load Balancer
# created for the Kong Service; databases, Kafka, Kong Admin, Prometheus and Grafana are
# ClusterIP-only (see k8s/azure).
resource "azurerm_virtual_network" "main" {
  name                = local.names.vnet
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "aks" {
  name                 = local.names.aks_subnet
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]
}
