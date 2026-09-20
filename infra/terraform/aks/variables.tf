variable "subscription_id" {
  description = "ID da assinatura Azure. Prefira exportar ARM_SUBSCRIPTION_ID/usar o service connection e deixar vazio."
  type        = string
  default     = ""
}

variable "location" {
  description = "Regiao Azure onde o AKS e recursos novos serao criados. Mantida igual ao stack App Service."
  type        = string
  default     = "westus3"
}

variable "suffix" {
  description = "Sufixo minusculo alfanumerico usado para gerar nomes globais unicos deste stack (RG, AKS, Log Analytics)."
  type        = string
  default     = "aks01"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.suffix))
    error_message = "O sufixo deve ter de 3 a 10 caracteres minusculos alfanumericos."
  }
}

variable "resource_group_name" {
  description = "Nome do Resource Group criado por este stack para os recursos do AKS."
  type        = string
  default     = ""
}

variable "aks_node_count" {
  type    = number
  default = 1
}

variable "aks_node_size" {
  description = "SKU do node pool padrao. Confirme cota disponivel na regiao antes de mudar."
  type        = string
  default     = "Standard_D4s_v5"
}

# --- Recursos EXISTENTES, criados pelo stack infra/terraform/appservice, ---
# --- referenciados aqui via data source (nao sao geridos por este state). ---

variable "shared_resource_group_name" {
  description = "Resource Group onde ja existem o ACR, o Azure SQL e o Key Vault (stack App Service)."
  type        = string
  default     = "rg-azureshop-shop01"
}

variable "acr_name" {
  description = "Nome do ACR existente a ser reaproveitado pelo AKS (mesmo do App Service)."
  type        = string
  default     = "acrazureshopshop01"
}

variable "sql_server_name" {
  description = "Nome do Azure SQL Server dedicado ao AKS, criado por este stack."
  type        = string
  default     = ""
}

variable "sql_database_name" {
  type    = string
  default = "azureshop"
}

variable "sql_sku_name" {
  description = "SKU do banco Azure SQL dedicado ao AKS (serverless barato: GP_S_Gen5_1)."
  type        = string
  default     = "GP_S_Gen5_1"
}

variable "sql_admin_login" {
  description = "Login administrativo do Azure SQL dedicado ao AKS."
  type        = string
  default     = "azureshopadmin"
}

variable "allow_azure_services" {
  description = "Libera 0.0.0.0 no firewall do SQL para que o AKS (sem VNet integration com o SQL) alcance o banco."
  type        = bool
  default     = false
}

variable "sql_public_network_access" {
  description = "Mantem o acesso publico ao Azure SQL habilitado. Para uso via Private Endpoint, mantenha false."
  type        = bool
  default     = false
}

variable "key_vault_name" {
  description = "Nome do Key Vault existente onde a senha do SQL ja esta armazenada (secret 'sql-admin-password')."
  type        = string
  default     = "kv-azshop2-shop01"
}

variable "tags" {
  type = map(string)
  default = {
    project = "azureshop"
    managed = "terraform"
    target  = "aks"
  }
}
