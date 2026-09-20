locals {
  tags                = var.tags
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-azureshop-aks-${var.suffix}"
  aks_name            = "aks-azureshop-${var.suffix}"
  monitoring_name     = "azureshop-aks-${var.suffix}"
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

data "azurerm_mssql_server" "shared" {
  name                = var.sql_server_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

data "azurerm_mssql_database" "shared" {
  name      = var.sql_database_name
  server_id = data.azurerm_mssql_server.shared.id
}

data "azurerm_key_vault" "shared" {
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# Senha ja gerada e armazenada pelo stack App Service; nunca versionada em texto claro aqui.
data "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  key_vault_id = data.azurerm_key_vault.shared.id
}

# --- Recursos novos deste stack ---

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
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

# Espelha no Key Vault compartilhado os valores no formato esperado pelo
# SecretProviderClass (infra/k8s/secretproviderclass.yaml). O valor da senha e
# lido do secret ja existente, nunca reescrito em texto claro no state deste
# stack alem da referencia ao data source acima (Terraform trata como sensitive).
resource "azurerm_key_vault_secret" "sql_server" {
  name         = "sql-server"
  value        = data.azurerm_mssql_server.shared.fully_qualified_domain_name
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags
}

resource "azurerm_key_vault_secret" "sql_database" {
  name         = "sql-database"
  value        = data.azurerm_mssql_database.shared.name
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags
}

resource "azurerm_key_vault_secret" "sql_user" {
  name         = "sql-user"
  value        = var.sql_admin_login
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags
}

resource "azurerm_key_vault_secret" "sql_password" {
  name         = "sql-password"
  value        = data.azurerm_key_vault_secret.sql_admin_password.value
  key_vault_id = data.azurerm_key_vault.shared.id
  tags         = local.tags
}
