variable "environment" {
  type = string
}

variable "matrix_domain" {
  type = string
}

variable "homeserver_url" {
  type = string
}

variable "synapse_admin_token" {
  type      = string
  sensitive = true
}

variable "redis_url" {
  type = string
}

variable "prometheus_url" {
  type = string
}

variable "tags" {
  type = map(string)
}
