variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "app_name" { type = string }
variable "plan_name" {
  type    = string
  default = ""
}
variable "plan_sku" { type = string }
variable "virtual_network_subnet_id" {
  description = "ID da subnet exclusiva delegada a Microsoft.Web/serverFarms para VNet Integration de saida."
  type        = string
  default     = ""
}

variable "acr_login_server" {
  description = "Login server do ACR usado para pull da imagem do container (ex.: acrazureshop.azurecr.io)."
  type        = string
  default     = ""
}

variable "docker_image_name" {
  description = "Repositorio da imagem dentro do ACR (sem tag), ex.: azureshop."
  type        = string
  default     = "azureshop"
}

variable "docker_image_tag" {
  description = "Tag inicial da imagem. A pipeline atualiza a tag em producao via az cli apos o build."
  type        = string
  default     = "latest"
}

variable "app_insights_connection_string" {
  type      = string
  default   = ""
  sensitive = true
}

variable "db_provider" {
  type    = string
  default = "sqlserver"
}

variable "sql_server_fqdn" {
  type    = string
  default = ""
}

variable "sql_database_name" {
  type    = string
  default = ""
}

variable "sql_admin_login" {
  type    = string
  default = ""
}

variable "sql_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "ai_enabled" {
  type    = bool
  default = false
}

resource "azurerm_service_plan" "this" {
  name                = var.plan_name != "" ? var.plan_name : "plan-${var.app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.plan_sku
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                      = var.app_name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.this.id
  virtual_network_subnet_id = var.virtual_network_subnet_id != "" ? var.virtual_network_subnet_id : null
  https_only                = true
  tags                      = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = "/api/health"
    health_check_eviction_time_in_min       = 2
    always_on                               = true
    container_registry_use_managed_identity = true

    application_stack {
      docker_image_name   = "${var.docker_image_name}:${var.docker_image_tag}"
      docker_registry_url = "https://${var.acr_login_server}"
    }
  }

  app_settings = {
    APP_ENV                               = "azure"
    DB_PROVIDER                           = var.db_provider
    AZURE_SQL_SERVER                      = var.sql_server_fqdn
    AZURE_SQL_DATABASE                    = var.sql_database_name
    AZURE_SQL_USER                        = var.sql_admin_login
    AZURE_SQL_PASSWORD                    = var.sql_admin_password
    AI_ENABLED                            = tostring(var.ai_enabled)
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    WEBSITES_PORT                         = "3000"
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
  }

  # A pipeline atualiza a tag da imagem via 'az webapp config container set' a
  # cada deploy; o Terraform nao deve reverter essa mudanca no proximo apply.
  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

output "name" { value = azurerm_linux_web_app.this.name }
output "url" { value = "https://${azurerm_linux_web_app.this.default_hostname}" }
output "principal_id" { value = azurerm_linux_web_app.this.identity[0].principal_id }
output "plan_id" { value = azurerm_service_plan.this.id }
