variable "virtual_environment_endpoint" {
  type        = string
  description = "A URL da API do Proxmox"
}

variable "virtual_environment_api_token" {
  type        = string
  description = "Token combinado do Proxmox"
  sensitive   = true
}
