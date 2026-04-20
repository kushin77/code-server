variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "prod"
}

variable "synapse_homeserver_url" {
  type        = string
  description = "Synapse homeserver URL (e.g., https://matrix.kushnir.cloud)"
}

variable "google_client_id" {
  type        = string
  description = "Google OAuth 2.0 client ID"
  sensitive   = true
}

variable "google_client_secret" {
  type        = string
  description = "Google OAuth 2.0 client secret"
  sensitive   = true
}

variable "allowed_email_domain" {
  type        = string
  description = "Restrict logins to this email domain (e.g., kushnir.cloud)"
  default     = "kushnir.cloud"
}

variable "synapse_admin_token" {
  type        = string
  description = "Synapse admin token for user provisioning"
  sensitive   = true
}

variable "synapse_database_url" {
  type        = string
  description = "PostgreSQL connection string for Synapse"
  sensitive   = true
}

variable "auto_provision_users" {
  type        = bool
  description = "Automatically create Matrix accounts on first OIDC login"
  default     = true
}

variable "sync_display_name" {
  type        = bool
  description = "Sync display name from Google profile"
  default     = true
}

variable "deprovisioning_enabled" {
  type        = bool
  description = "Enable user deprovisioning via SCIM (Phase 2)"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
