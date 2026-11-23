variable "subscription_id" {
  description = "Azure subscription that hosts the environment."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource names and tags (e.g. demo)."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region. eastus2 is cheaper than brazilsouth for the same VM sizes (see docs/phase4/COSTS.md)."
  type        = string
  default     = "eastus2"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. null = the region's default GA version."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size of the single system/user node pool."
  type        = string
  default     = "Standard_D4as_v5"
}

variable "node_count" {
  description = "Number of nodes. One node is enough for the demo workload (Elasticsearch is external)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 3
    error_message = "node_count must be between 1 and 3 for this environment."
  }
}

variable "vnet_address_space" {
  description = "Address space of the environment VNet."
  type        = string
  default     = "10.20.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "Subnet for AKS nodes (pods use the overlay CIDR below)."
  type        = string
  default     = "10.20.0.0/22"
}

variable "pod_cidr" {
  description = "Azure CNI Overlay pod CIDR (must not overlap the VNet)."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap the VNet)."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS service IP, inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "api_server_authorized_ip_ranges" {
  description = "Optional CIDRs allowed to reach the Kubernetes API. Empty = public API (GitHub-hosted runners have no fixed IPs)."
  type        = list(string)
  default     = []
}

variable "namespace" {
  description = "Kubernetes namespace of the application workloads."
  type        = string
  default     = "fcg"
}

variable "github_owner" {
  description = "GitHub user/organization that owns the service repositories."
  type        = string
  default     = "allanmoraesprado"
}

variable "github_deploy_repositories" {
  description = "Repositories whose workflows may deploy (OIDC trust restricted to their main branch)."
  type        = list(string)
  default = [
    "fiap-cloud-games-users-api",
    "fiap-cloud-games-catalog-api",
    "fiap-cloud-games-payments-api",
    "fiap-cloud-games-notifications-function",
  ]
}

variable "github_oidc_subject_prefixes" {
  description = "Per-repository OIDC subject prefix when it is not repo:<owner>/<repo> (repositories using GitHub immutable subject claims). Find it with: gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = map(string)
  default     = {}
}

variable "budget_amount" {
  description = "Monthly budget (billing currency) for the environment resource groups. 0 disables the budget."
  type        = number
  default     = 50
}

variable "budget_contact_emails" {
  description = "Extra e-mails notified by the budget alerts (subscription Owners are always notified). Keep them in terraform.tfvars (not committed)."
  type        = list(string)
  default     = []
}

variable "budget_start_date" {
  description = "First day of the month the budget starts (RFC3339), e.g. 2026-12-01T00:00:00Z."
  type        = string
  default     = "2026-12-01T00:00:00Z"
}

variable "secrets_version" {
  description = "Bump to regenerate every generated secret (passwords, JWT key, derived connection strings) on the next apply."
  type        = number
  default     = 1
}

variable "elasticsearch_url" {
  description = "Elastic Cloud HTTPS endpoint. Not a secret, but stored next to the API key in Key Vault."
  type        = string
  default     = "https://elasticsearch-not-configured.invalid:443"
}

variable "elasticsearch_api_key" {
  description = "Elastic Cloud API key (base64 'encoded' value). Ephemeral: written to Key Vault, never stored in state."
  type        = string
  default     = "not-configured"
  sensitive   = true
  ephemeral   = true
}

variable "elasticsearch_secret_version" {
  description = "Bump after changing elasticsearch_url / elasticsearch_api_key so the new values are written."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Extra tags merged into the default tags."
  type        = map(string)
  default     = {}
}
