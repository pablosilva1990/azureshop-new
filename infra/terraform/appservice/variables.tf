variable "subscription_id" {
  description = "ID da assinatura Azure. Prefira exportar ARM_SUBSCRIPTION_ID/usar o service connection e deixar vazio."
  type        = string
  default     = ""
}

variable "location" {
  description = "Regiao Azure onde todos os recursos serao criados."
  type        = string
  default     = "westus3"
}

variable "suffix" {
  description = "Sufixo minusculo alfanumerico usado para gerar nomes globais unicos (ACR, SQL, Key Vault, App Service)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.suffix))
    error_message = "O sufixo deve ter de 3 a 10 caracteres minusculos alfanumericos."
  }
}

variable "resource_group_name" {
  description = "Nome do Resource Group criado por este stack (self-contained, sem dependencia de recursos manuais)."
  type        = string
  default     = ""
}

variable "acr_sku" {
  type    = string
  default = "Basic"
}

variable "app_service_sku" {
  description = "SKU do App Service Plan Linux. B1 e o minimo que suporta always_on e VNet integration."
  type        = string
  default     = "B1"
}

variable "docker_image_name" {
  description = "Repositorio da imagem dentro do ACR (sem tag)."
  type        = string
  default     = "azureshop"
}

variable "docker_image_tag" {
  description = "Tag inicial da imagem publicada no App Service. A pipeline atualiza a tag a cada deploy via az cli."
  type        = string
  default     = "latest"
}

variable "sql_admin_login" {
  description = "Login administrativo do Azure SQL Server."
  type        = string
  default     = "azureshopadmin"
}

variable "sql_database_name" {
  type    = string
  default = "azureshop"
}

variable "sql_sku_name" {
  description = "SKU do banco Azure SQL (serverless barato para laboratorio: GP_S_Gen5_1)."
  type        = string
  default     = "GP_S_Gen5_1"
}

variable "allow_azure_services" {
  description = "Libera 0.0.0.0 no firewall do SQL para que o App Service (sem VNet integration) alcance o banco."
  type        = bool
  default     = true
}

variable "allowed_source_ip" {
  description = "IP/CIDR opcional liberado no firewall do SQL para acesso administrativo (ex.: da maquina do desenvolvedor)."
  type        = string
  default     = ""
}

variable "ai_enabled" {
  description = "Habilita a integracao com Azure OpenAI na aplicacao (requer configuracao adicional fora deste stack)."
  type        = bool
  default     = false
}

variable "pipeline_service_principal_object_id" {
  description = "Object ID do Service Principal usado pela pipeline (service connection do Azure DevOps). Recebe AcrPush para publicar imagens."
  type        = string
  default     = ""
}

variable "tags" {
  type = map(string)
  default = {
    project = "azureshop"
    managed = "terraform"
  }
}
