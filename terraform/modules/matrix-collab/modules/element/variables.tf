variable "environment" {
  type = string
}

variable "matrix_domain" {
  type = string
}

variable "apex_domain" {
  type = string
}

variable "homeserver_url" {
  type = string
}

variable "docker_image" {
  type    = string
  default = "vectorim/element-web:latest"
}

variable "tags" {
  type = map(string)
}
