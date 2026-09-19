output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "acr_name" {
  value = module.container_registry.name
}

output "acr_login_server" {
  value = module.container_registry.login_server
}

output "app_service_name" {
  value = module.app_service.name
}

output "app_service_url" {
  value = module.app_service.url
}

output "app_service_principal_id" {
  value = module.app_service.principal_id
}

output "sql_server_fqdn" {
  value = module.sql_database.server_fqdn
}

output "sql_database_name" {
  value = module.sql_database.database_name
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "app_insights_connection_string" {
  value     = module.monitoring.app_insights_connection_string
  sensitive = true
}
