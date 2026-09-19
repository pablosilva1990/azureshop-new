variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "sql_location" {
  type    = string
  default = ""
}
variable "tags" { type = map(string) }
variable "server_name" { type = string }
variable "database_name" { type = string }
variable "sku_name" { type = string }
variable "admin_login" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "entra_admin_login" {
  type    = string
  default = ""
}
variable "entra_admin_object_id" {
  type    = string
  default = ""
}
variable "allow_azure_services" {
  type    = bool
  default = false
}
variable "allowed_source_ip" {
  type    = string
  default = ""
}
variable "subnet_id" {
  type    = string
  default = ""
}
variable "vnet_id" {
  type    = string
  default = ""
}
variable "aks_vnet_id" {
  type    = string
  default = ""
}
variable "enable_private_endpoint" {
  type    = bool
  default = false
}
variable "public_network_access" {
  type    = bool
  default = true
}
variable "min_capacity" {
  description = "vCores minimos para SKUs serverless (GP_S_*). Obrigatorio nesses SKUs; ignorado nos demais."
  type        = number
  default     = 0.5
}
variable "auto_pause_delay_in_minutes" {
  description = "Minutos de ociosidade antes de pausar um banco serverless (GP_S_*). -1 desativa o auto-pause."
  type        = number
  default     = 60
}

locals {
  sql_region = var.sql_location != "" ? var.sql_location : var.location
}

resource "azurerm_mssql_server" "this" {
  name                          = var.server_name
  resource_group_name           = var.resource_group_name
  location                      = local.sql_region
  version                       = "12.0"
  administrator_login           = var.admin_login
  administrator_login_password  = var.admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = var.public_network_access
  tags                          = var.tags

  dynamic "azuread_administrator" {
    for_each = var.entra_admin_login != "" && var.entra_admin_object_id != "" ? [1] : []
    content {
      login_username = var.entra_admin_login
      object_id      = var.entra_admin_object_id
    }
  }
}

resource "azurerm_mssql_database" "this" {
  name        = var.database_name
  server_id   = azurerm_mssql_server.this.id
  sku_name    = var.sku_name
  collation   = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb = 2
  tags        = var.tags

  # SKUs serverless (GP_S_*) exigem min_capacity/auto_pause_delay_in_minutes explicitos.
  min_capacity                = startswith(var.sku_name, "GP_S_") ? var.min_capacity : null
  auto_pause_delay_in_minutes = startswith(var.sku_name, "GP_S_") ? var.auto_pause_delay_in_minutes : null
}

# Regra temporaria para o IP do instrutor (apenas durante o laboratorio).
resource "azurerm_mssql_firewall_rule" "instructor" {
  count            = var.allowed_source_ip != "" ? 1 : 0
  name             = "AllowInstructorIp"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = split("/", var.allowed_source_ip)[0]
  end_ip_address   = split("/", var.allowed_source_ip)[0]
}

# Opcao explicita para permitir Servicos do Azure (0.0.0.0) somente no laboratorio.
resource "azurerm_mssql_firewall_rule" "azure_services" {
  count            = var.allow_azure_services ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ---------------------------------------------------------------------------
# Private Endpoint (Private Link) — Azure SQL acessivel por IP privado na VNet
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "sql" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "privatelink.database.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Vincula a Zona DNS Privada a VNet da aplicacao (vnet-imersao).
resource "azurerm_private_dns_zone_virtual_network_link" "vnet" {
  count                 = var.enable_private_endpoint && var.vnet_id != "" ? 1 : 0
  name                  = "link-vnet-imersao"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# Vincula a mesma Zona DNS Privada a VNet gerenciada do AKS (via peering),
# para que os pods resolvam o FQDN do SQL para o IP privado.
resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.enable_private_endpoint && var.aks_vnet_id != "" ? 1 : 0
  name                  = "link-aks-vnet"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = var.aks_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "sql" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-${var.server_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sql"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sql-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql[0].id]
  }
}

output "server_fqdn" { value = azurerm_mssql_server.this.fully_qualified_domain_name }
output "database_name" { value = azurerm_mssql_database.this.name }
output "server_id" { value = azurerm_mssql_server.this.id }