# Monthly cost guardrail. Filtered to the environment resource group AND the AKS node
# resource group (the VM, disks, IPs and load balancer are billed there).
resource "azurerm_consumption_budget_subscription" "main" {
  count = var.budget_amount > 0 && length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = local.names.budget
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  filter {
    dimension {
      name     = "ResourceGroupName"
      operator = "In"
      values   = [azurerm_resource_group.main.name, local.names.node_rg]
    }
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
