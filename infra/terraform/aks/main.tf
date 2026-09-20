locals {
  tags                = var.tags
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-azureshop-aks-${var.suffix}"
  aks_name            = "aks-azureshop-${var.suffix}"
  monitoring_name     = "azureshop-aks-${var.suffix}"
  sql_server_name     = var.sql_server_name != "" ? var.sql_server_name : "sql-azureshop-${var.suffix}"
}

data "azurerm_client_config" "current" {}

# --- Recursos existentes reaproveitados (geridos pelo stack infra/terraform/appservice) ---

data "azurerm_resource_group" "shared" {
  name = var.shared_resource_group_name
}

data "azurerm_container_registry" "shared" {
  name                = var.acr_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

data "azurerm_key_vault" "shared" {
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# --- Recursos novos deste stack ---

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# Azure SQL dedicado ao AKS (o servidor original do App Service foi excluido).
resource "random_password" "sql_admin" {
  length           = 24
  special          = true
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "-_=+"
}

module "sql_database" {
  source              = "../modules/sql-database"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  server_name         = local.sql_server_name
  database_name       = var.sql_database_name
  sku_name            = var.sql_sku_name
  admin_login         = var.sql_admin_login
  admin_password      = random_password.sql_admin.result

  allow_azure_services = var.allow_azure_services
}

module "monitoring" {
  source              = "../modules/monitoring"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  name                = local.monitoring_name
}

module "aks" {
  source              = "../modules/aks"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  aks_name            = local.aks_name
  node_count          = var.aks_node_count
  node_size           = var.aks_node_size

  log_analytics_workspace_id = module.monitoring.workspace_id
}

# Least privilege: kubelet identity so recebe permissao de puxar imagens do ACR existente.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_object_id
}

# Least privilege: a identidade do Key Vault Secrets Provider (CSI driver) so pode LER
# secrets do Key Vault existente, nunca escrever/gerenciar (Secrets User, nao Officer).
resource "azurerm_role_assignment" "aks_kv_secrets_user" {
  scope                = data.azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.aks.key_vault_secrets_provider_object_id
}

# Deployer precisa gerenciar secrets para gravar as credenciais do novo SQL no Key Vault.
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = data.azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Espelha no Key Vault compartilhado os valores no formato esperado pelo
# SecretProviderClass (infra/k8s/secretproviderclass.yaml), apontando para o
# Azure SQL dedicado do AKS.
resource "azurerm_key_vault_secret" "sql_server" {
  name         = "sql-server"
  value        = module.sql_database.server_fqdn
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "sql_database" {
  name         = "sql-database"
  value        = module.sql_database.database_name
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "sql_user" {
  name         = "sql-user"
  value        = var.sql_admin_login
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "sql_password" {
  name         = "sql-password"
  value        = random_password.sql_admin.result
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}
