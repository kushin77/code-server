variable "region" {
  type = string
}

variable "matrix_domain" {
  type = string
}

variable "apex_domain" {
  type = string
}

variable "google_client_id" {
  type      = string
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  sensitive = true
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

variable "docker_image" {
  type    = string
  default = "matrixdotorg/synapse:latest"
}

variable "postgres_version" {
  type    = string
  default = "15"
}

variable "max_upload_size" {
  type    = number
  default = 52428800
}

variable "db_pool_size" {
  type    = number
  default = 25
}

variable "tags" {
  type = map(string)
}
