locals {
  tags                = var.tags
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-azureshop-${var.suffix}"
  acr_name            = "acrazureshop${var.suffix}"
  sql_server_name     = "sql-azureshop-${var.suffix}"
  key_vault_name      = var.key_vault_name != "" ? var.key_vault_name : "kv-azshop-${var.suffix}"
  app_name            = "app-azureshop-${var.suffix}"
  monitoring_name     = "azureshop-${var.suffix}"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# Senha do administrador do Azure SQL. Gerada uma unica vez e persistida no
# state remoto; nunca versionada em texto claro no repositorio.
resource "random_password" "sql_admin" {
  length      = 24
  special     = true
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
  # Caracteres aceitos pelo Azure SQL e sem ambiguidade em variaveis de shell.
  override_special = "-_=+"
}

module "container_registry" {
  source              = "../modules/container-registry"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  acr_name            = local.acr_name
  sku                 = var.acr_sku
}

module "monitoring" {
  source              = "../modules/monitoring"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  name                = local.monitoring_name
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
  allowed_source_ip    = var.allowed_source_ip
}

module "key_vault" {
  source              = "../modules/key-vault"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  key_vault_name      = local.key_vault_name
  public_access       = true
}

# Quem roda o Terraform precisa gerenciar segredos para poder gravar a senha
# do SQL no Key Vault (RBAC, sem access policies).
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = random_password.sql_admin.result
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

module "app_service" {
  source              = "../modules/app-service"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  app_name            = local.app_name
  plan_sku            = var.app_service_sku

  acr_login_server  = module.container_registry.login_server
  docker_image_name = var.docker_image_name
  docker_image_tag  = var.docker_image_tag

  db_provider        = "sqlserver"
  sql_server_fqdn    = module.sql_database.server_fqdn
  sql_database_name  = module.sql_database.database_name
  sql_admin_login    = var.sql_admin_login
  sql_admin_password = random_password.sql_admin.result
  ai_enabled         = var.ai_enabled

  app_insights_connection_string = module.monitoring.app_insights_connection_string
}

# Permite que o App Service puxe imagens do ACR via managed identity, sem
# usuario/senha de admin do registry.
resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.app_service.principal_id
}

resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service.principal_id
}

# Da ao Service Principal da pipeline permissao para publicar imagens (az acr
# build/push) sem depender das credenciais de admin do ACR.
resource "azurerm_role_assignment" "pipeline_acr_push" {
  count                = var.pipeline_service_principal_object_id != "" ? 1 : 0
  scope                = module.container_registry.id
  role_definition_name = "AcrPush"
  principal_id         = var.pipeline_service_principal_object_id
}
