locals {
  tags = {
    project = "azureshop"
    company = "highexpert"
    managed = "terraform"
  }

  acr_name = "acrimersao${var.suffix}"
  aks_name = "aks-imersao-${var.suffix}"
}

# Dia 1 e feito pelo Portal. Estes data sources impedem que o Dia 2 tente
# recriar os recursos manuais e falham cedo se o handoff estiver incompleto.
data "azurerm_resource_group" "portal" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "portal" {
  name                = var.portal_vnet_name
  resource_group_name = data.azurerm_resource_group.portal.name
}

data "azurerm_subnet" "portal_data" {
  name                 = var.portal_data_subnet_name
  virtual_network_name = data.azurerm_virtual_network.portal.name
  resource_group_name  = data.azurerm_resource_group.portal.name
}

data "azurerm_network_security_group" "portal_data" {
  name                = var.portal_data_nsg_name
  resource_group_name = data.azurerm_resource_group.portal.name
}

data "azurerm_mssql_server" "portal" {
  name                = var.portal_sql_server_name
  resource_group_name = data.azurerm_resource_group.portal.name
}

data "azurerm_mssql_database" "portal" {
  name      = var.portal_sql_database_name
  server_id = data.azurerm_mssql_server.portal.id
}

data "azurerm_private_dns_zone" "portal_sql" {
  name                = var.portal_sql_private_dns_zone_name
  resource_group_name = data.azurerm_resource_group.portal.name
}

# Dia 2, fase 1: cria apenas os recursos novos da camada de containers.
module "container_registry" {
  source              = "./modules/container-registry"
  count               = var.deploy_acr ? 1 : 0
  resource_group_name = data.azurerm_resource_group.portal.name
  location            = data.azurerm_resource_group.portal.location
  tags                = local.tags
  acr_name            = local.acr_name
  sku                 = var.acr_sku
}

module "aks" {
  source              = "./modules/aks"
  count               = var.deploy_aks ? 1 : 0
  resource_group_name = data.azurerm_resource_group.portal.name
  location            = data.azurerm_resource_group.portal.location
  tags                = local.tags
  aks_name            = local.aks_name
  node_count          = var.aks_node_count
  node_size           = var.aks_node_size
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.deploy_acr && var.deploy_aks ? 1 : 0
  scope                = module.container_registry[0].id
  role_definition_name = "AcrPull"
  principal_id         = module.aks[0].kubelet_object_id
}

# Dia 2, fase 2: informe os nomes coletados apos a criacao do AKS. A VNet
# gerenciada e descoberta por data source antes de configurar o caminho privado.
data "azurerm_virtual_network" "aks" {
  count               = var.deploy_aks && var.enable_aks_private_connectivity ? 1 : 0
  name                = var.aks_vnet_name
  resource_group_name = var.aks_node_resource_group
}

resource "azurerm_virtual_network_peering" "portal_to_aks" {
  count                        = var.enable_aks_private_connectivity ? 1 : 0
  name                         = "peer-imersao-to-aks-${var.suffix}"
  resource_group_name          = data.azurerm_virtual_network.portal.resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.portal.name
  remote_virtual_network_id    = data.azurerm_virtual_network.aks[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "aks_to_portal" {
  count                        = var.enable_aks_private_connectivity ? 1 : 0
  name                         = "peer-aks-to-imersao-${var.suffix}"
  resource_group_name          = var.aks_node_resource_group
  virtual_network_name         = data.azurerm_virtual_network.aks[0].name
  remote_virtual_network_id    = data.azurerm_virtual_network.portal.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.enable_aks_private_connectivity ? 1 : 0
  name                  = "link-aks-vnet-${var.suffix}"
  resource_group_name   = data.azurerm_resource_group.portal.name
  private_dns_zone_name = data.azurerm_private_dns_zone.portal_sql.name
  virtual_network_id    = data.azurerm_virtual_network.aks[0].id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_network_security_rule" "aks_to_sql" {
  count                       = var.enable_aks_private_connectivity ? 1 : 0
  name                        = "Allow-AKS-To-SQL-1433"
  priority                    = var.aks_sql_nsg_priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefixes     = var.aks_vnet_address_prefixes
  destination_address_prefix  = data.azurerm_subnet.portal_data.address_prefixes[0]
  resource_group_name         = data.azurerm_network_security_group.portal_data.resource_group_name
  network_security_group_name = data.azurerm_network_security_group.portal_data.name

  lifecycle {
    precondition {
      condition     = var.aks_vnet_name != "" && var.aks_node_resource_group != "" && length(var.aks_vnet_address_prefixes) > 0
      error_message = "Informe a VNet, o Resource Group gerenciado e os prefixos reais do AKS antes da fase 2."
    }
  }
}
