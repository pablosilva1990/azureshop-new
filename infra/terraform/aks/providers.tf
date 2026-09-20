terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2, < 5.0"
    }
  }

  # Preenchido em runtime pela pipeline via TerraformTaskV4 (backendAzureRm*),
  # reaproveitando a mesma Storage Account de state do stack App Service, com
  # uma 'key' de blob diferente. Para uso local, rode:
  #   terraform init -backend-config="resource_group_name=<rg>" \
  #     -backend-config="storage_account_name=<sa>" \
  #     -backend-config="container_name=tfstate" \
  #     -backend-config="key=azureshop-aks.tfstate"
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id != "" ? var.subscription_id : null

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
