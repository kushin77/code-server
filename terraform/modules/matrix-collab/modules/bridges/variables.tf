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

variable "enable_slack_bridge" {
  type    = bool
  default = true
}

variable "enable_teams_bridge" {
  type    = bool
  default = false
}

variable "enable_google_chat_bridge" {
  type    = bool
  default = false
}

variable "primary_chat_platform" {
  type    = string
  default = "slack"
}

variable "tags" {
  type = map(string)
}
