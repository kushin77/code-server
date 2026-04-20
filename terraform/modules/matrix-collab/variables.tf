variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
  default     = "prod"
}

variable "matrix_domain" {
  type        = string
  description = "Domain for Matrix homeserver (e.g., matrix.example.com)"
}

variable "apex_domain" {
  type        = string
  description = "Apex domain for all services"
}

variable "primary_chat_platform" {
  type        = string
  description = "Primary chat platform (slack, teams, google-chat)"
  default     = "slack"
}

variable "google_client_id" {
  type        = string
  description = "Google OAuth client ID for OIDC"
  sensitive   = true
  default     = ""
}

variable "google_client_secret" {
  type        = string
  description = "Google OAuth client secret for OIDC"
  sensitive   = true
  default     = ""
}

variable "synapse_admin_token" {
  type        = string
  description = "Admin token for Synapse server"
  sensitive   = true
  default     = ""
}

variable "redis_url" {
  type        = string
  description = "Redis connection URL"
  default     = "redis://redis:6379"
}

variable "prometheus_url" {
  type        = string
  description = "Prometheus metrics URL"
  default     = "http://prometheus:9090"
}

variable "enable_slack_bridge" {
  type        = bool
  description = "Enable Slack bridge"
  default     = true
}

variable "enable_teams_bridge" {
  type        = bool
  description = "Enable Microsoft Teams bridge"
  default     = false
}

variable "enable_google_chat_bridge" {
  type        = bool
  description = "Enable Google Chat bridge"
  default     = false
}

variable "enable_presence_sidecar" {
  type        = bool
  description = "Enable presence sidecar for real-time status"
  default     = true
}

variable "enable_element_call" {
  type        = bool
  description = "Enable Element Call for VoIP/video conferencing"
  default     = false
}

variable "docker_image_synapse" {
  type        = string
  description = "Synapse Docker image"
  default     = "matrixdotorg/synapse:latest"
}

variable "docker_image_element" {
  type        = string
  description = "Element web client Docker image"
  default     = "vectorim/element-web:latest"
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL version for Synapse"
  default     = "15"
}

variable "synapse_max_upload_size" {
  type        = number
  description = "Maximum upload size in bytes"
  default     = 52428800  # 50MB
}

variable "synapse_db_pool_size" {
  type        = number
  description = "Database connection pool size"
  default     = 25
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
