terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }

  # Local state on purpose (temporary demo environment). The state contains generated
  # secrets: never commit it (see .gitignore) and delete it after `terraform destroy`.
  # For a shared environment use the azurerm backend instead (see backend.tf.example).
}
