# Variables for Matrix Governance Module

variable "enable_admin_bot" {
  type        = bool
  default     = true
  description = "Enable Matrix admin bot for space/template management"
}

variable "enable_retention_policies" {
  type        = bool
  default     = true
  description = "Enable retention policy management"
}

variable "enable_space_templates" {
  type        = bool
  default     = true
  description = "Enable space template system"
}

variable "enable_audit_logging" {
  type        = bool
  default     = true
  description = "Enable audit logging for Matrix events"
}

variable "enable_moderation" {
  type        = bool
  default     = true
  description = "Enable moderation tooling (content filters, rate limiting)"
}

variable "enable_retention_purge_job" {
  type        = bool
  default     = true
  description = "Enable scheduled retention purge job"
}

variable "use_kubernetes" {
  type        = bool
  default     = false
  description = "Use Kubernetes CronJob for retention purge instead of Docker"
}

# Admin Bot Configuration
variable "admin_bot_image" {
  type        = string
  default     = "kushin77/matrix-admin-bot"
  description = "Docker image for Matrix admin bot"
}

variable "admin_bot_version" {
  type        = string
  default     = "latest"
  description = "Version tag for admin bot image"
}

variable "admin_bot_token" {
  type        = string
  sensitive   = true
  description = "Matrix access token for admin bot (from GSM or env)"
}

variable "admin_user_id" {
  type        = string
  description = "Matrix user ID for admin bot (e.g., @admin:matrix.example.com)"
}

variable "homeserver_url" {
  type        = string
  description = "Synapse homeserver URL"
  default     = "http://synapse:8008"
}

variable "docker_network_id" {
  type        = string
  description = "Docker network ID for container communication"
}

# Retention Policy Configuration
variable "retention_enabled" {
  type        = bool
  default     = true
  description = "Enable retention policies"
}

variable "retention_default_max_lifetime" {
  type        = string
  default     = "90d"
  description = "Default maximum retention lifetime"
}

variable "retention_default_min_lifetime" {
  type        = string
  default     = "1d"
  description = "Default minimum retention lifetime"
}

variable "retention_allowed_policies" {
  type = list(object({
    max_lifetime = string
  }))
  default = [
    { max_lifetime = "7d" },    # Ephemeral
    { max_lifetime = "30d" },   # Short-term
    { max_lifetime = "90d" },   # Default
    { max_lifetime = "365d" },  # Long-term
    { max_lifetime = "730d" },  # Compliance
  ]
  description = "List of allowed retention policies"
}

variable "retention_purge_interval" {
  type        = string
  default     = "1d"
  description = "How often to run retention purge job"
}

variable "retention_max_rooms_per_run" {
  type        = number
  default     = 100
  description = "Maximum rooms to purge per job run"
}

variable "retention_default_max_lifetime_for_templates" {
  type = map(number)
  default = {
    team              = 90
    project           = 30
    public-announcements = 365
  }
  description = "Default retention days per space template"
}

# Space Template Configuration
variable "space_template_team_avatar" {
  type        = string
  default     = "mxc://example.com/team-avatar"
  description = "Avatar URL for team space template"
}

variable "space_template_project_avatar" {
  type        = string
  default     = "mxc://example.com/project-avatar"
  description = "Avatar URL for project space template"
}

variable "space_template_announcements_avatar" {
  type        = string
  default     = "mxc://example.com/announcements-avatar"
  description = "Avatar URL for announcements space template"
}

variable "space_template_team_retention" {
  type        = number
  default     = 90
  description = "Retention days for team spaces"
}

variable "space_template_project_retention" {
  type        = number
  default     = 30
  description = "Retention days for project spaces"
}

variable "space_template_announcements_retention" {
  type        = number
  default     = 365
  description = "Retention days for announcements space"
}

# Audit Logging Configuration
variable "audit_database_url" {
  type        = string
  sensitive   = true
  description = "PostgreSQL connection URL for audit logs"
}

variable "audit_retention_days" {
  type        = number
  default     = 90
  description = "How long to retain audit logs"
}

# Moderation Configuration
variable "content_filtering_enabled" {
  type        = bool
  default     = false
  description = "Enable content filtering (optional)"
}

variable "content_filter_action" {
  type        = string
  default     = "redact"
  description = "Action on filtered content: warn, redact, or ban"
}

variable "content_filter_patterns" {
  type        = list(string)
  default     = []
  description = "Regex patterns for content filtering"
}

variable "rate_limit_messages_per_minute" {
  type        = number
  default     = 60
  description = "Messages per minute before rate limit triggers"
}

variable "rate_limit_action" {
  type        = string
  default     = "warn"
  description = "Rate limit action: warn, mute, or kick"
}

variable "audit_logging_enabled" {
  type        = bool
  default     = true
  description = "Enable audit logging"
}

# File Paths
variable "config_path" {
  type        = string
  default     = "/etc/matrix"
  description = "Path to Matrix configuration directory"
}

variable "synapse_config_path" {
  type        = string
  default     = "/etc/matrix/synapse"
  description = "Path to Synapse configuration directory"
}

# PostgreSQL Configuration
variable "postgresql_database" {
  type        = string
  default     = "matrix"
  description = "PostgreSQL database name"
}

variable "postgresql_user" {
  type        = string
  default     = "matrix"
  description = "PostgreSQL user"
}

variable "log_level" {
  type        = string
  default     = "INFO"
  description = "Log level for admin bot"
}
