output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_name" {
  value = module.aks.name
}

output "aks_node_resource_group" {
  value = module.aks.node_resource_group
}

output "aks_get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${module.aks.name} --overwrite-existing"
}

output "acr_login_server" {
  value = data.azurerm_container_registry.shared.login_server
}

output "acr_name" {
  value = data.azurerm_container_registry.shared.name
}

output "key_vault_name" {
  value = data.azurerm_key_vault.shared.name
}

output "key_vault_secrets_provider_client_id" {
  description = "Client ID usado no SecretProviderClass (infra/k8s/secretproviderclass.yaml)."
  value       = module.aks.key_vault_secrets_provider_client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}
