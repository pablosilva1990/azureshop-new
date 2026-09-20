variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "aks_name" { type = string }
variable "node_count" {
  type    = number
  default = 1
}
variable "node_size" {
  type    = string
  default = "Standard_D4s_v5"
}
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
variable "network_policy" {
  description = "Motor de Network Policy do Azure CNI para segmentar trafego pod-a-pod. Vazio desativa."
  type        = string
  default     = "azure"
}
variable "azure_policy_enabled" {
  description = "Habilita o add-on Azure Policy para aplicar baselines de seguranca (Azure Policy for Kubernetes)."
  type        = bool
  default     = true
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.aks_name
  tags                = var.tags

  # Identidade e recursos exigidos pelo workshop.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Hardening: RBAC do Kubernetes e Azure Policy baseline.
  role_based_access_control_enabled = true
  azure_policy_enabled              = var.azure_policy_enabled

  default_node_pool {
    name                        = "system"
    node_count                  = var.node_count
    vm_size                     = var.node_size
    temporary_name_for_rotation = "temp"
    # Uma zona apenas para reduzir custo em laboratorio.
  }

  identity {
    type = "SystemAssigned"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = var.network_policy != "" ? var.network_policy : null
    load_balancer_sku = "standard"
  }

  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  # Microsoft Defender for Containers: deteccao de ameacas em runtime.
  dynamic "microsoft_defender" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }
}

output "name" { value = azurerm_kubernetes_cluster.this.name }
output "node_resource_group" { value = azurerm_kubernetes_cluster.this.node_resource_group }
output "kubelet_object_id" { value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id }
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
output "key_vault_secrets_provider_client_id" { value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].client_id }
output "key_vault_secrets_provider_object_id" { value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id }
output "secrets_provider_object_id" { value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id }
output "secrets_provider_client_id" { value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].client_id }
output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.this.name}"
}
