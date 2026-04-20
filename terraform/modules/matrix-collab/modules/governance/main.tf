# Matrix Admin & Governance Module
# Provides space templates, admin bot, retention policies, and moderation tooling

# Admin Bot Deployment
resource "docker_container" "matrix_admin_bot" {
  count = var.enable_admin_bot ? 1 : 0

  name  = "matrix-admin-bot"
  image = "${var.admin_bot_image}:${var.admin_bot_version}"

  networks_advanced {
    name = var.docker_network_id
  }

  env = [
    "MATRIX_HOMESERVER_URL=${var.homeserver_url}",
    "MATRIX_ACCESS_TOKEN=${var.admin_bot_token}",
    "MATRIX_ADMIN_USER=${var.admin_user_id}",
    "AUDIT_DATABASE_URL=${var.audit_database_url}",
    "AUDIT_RETENTION_DAYS=${var.audit_retention_days}",
    "LOG_LEVEL=${var.log_level}",
  ]

  restart_policy {
    condition = "unless-stopped"
  }

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:3001/health"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }

  labels = {
    "app"    = "matrix-admin-bot"
    "module" = "matrix-governance"
  }

  depends_on = []

  lifecycle {
    ignore_changes = [image]
  }
}

# Synapse Configuration Update for Retention Policies
resource "null_resource" "retention_policy_config" {
  count = var.enable_retention_policies ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      cat >> ${var.synapse_config_path}/homeserver.yaml << 'RETENTION'

# Retention Policy Configuration
retention:
  enabled: ${var.retention_enabled}
  default_policy:
    max_lifetime: ${var.retention_default_max_lifetime}
    min_lifetime: ${var.retention_default_min_lifetime}
  
  allowed_policies:
%{for policy in var.retention_allowed_policies~}
    - max_lifetime: ${policy.max_lifetime}
%{endfor~}
  
  purge_jobs:
    - interval: ${var.retention_purge_interval}
      max_rooms_per_run: ${var.retention_max_rooms_per_run}

RETENTION
    EOT
  }

  triggers = {
    synapse_config = var.synapse_config_path
  }
}

# Space Templates Configuration
resource "local_file" "space_templates" {
  count = var.enable_space_templates ? 1 : 0

  filename = "${var.config_path}/matrix-space-templates.yaml"

  content = <<-EOT
# Matrix Space Templates for Admin Bot

templates:
  team-default:
    display_name: "Team Space"
    avatar_url: "${var.space_template_team_avatar}"
    topic: "Default space for team collaboration"
    invite_only: true
    power_levels:
      users:
        "@admin": 100
      events:
        m.room.avatar: 50
        m.room.retention: 50
        m.room.topic: 50
        m.room.name: 50
      events_default: 0
      state_default: 50
      users_default: 0
    retention_days: ${var.space_template_team_retention}
    join_rule: "invite"

  project-default:
    display_name: "Project Space"
    avatar_url: "${var.space_template_project_avatar}"
    topic: "Temporary project collaboration space"
    invite_only: false
    power_levels:
      users:
        "@admin": 100
      events_default: 10
      state_default: 50
      users_default: 0
    retention_days: ${var.space_template_project_retention}
    join_rule: "knock"

  public-announcements:
    display_name: "Public Announcements"
    avatar_url: "${var.space_template_announcements_avatar}"
    topic: "Organization-wide announcements and updates"
    invite_only: false
    power_levels:
      users:
        "@admin": 100
      events_default: 0  # Users can only read
      state_default: 100  # Only admins can modify
      users_default: 0
    retention_days: ${var.space_template_announcements_retention}
    join_rule: "public"

EOT

  lifecycle {
    ignore_changes_all = true
  }
}

# Audit Logging Configuration
resource "postgresql_schema" "audit_logging" {
  count       = var.enable_audit_logging ? 1 : 0
  name        = "audit"
  database    = var.postgresql_database
  owner       = var.postgresql_user
  description = "Audit logging for Matrix events"
}

resource "postgresql_default_privileges" "audit_privileges" {
  count       = var.enable_audit_logging ? 1 : 0
  owner       = var.postgresql_user
  database    = var.postgresql_database
  schema      = postgresql_schema.audit_logging[0].name
  object_type = "TABLE"
  privileges  = ["SELECT", "INSERT"]
  role        = var.postgresql_user
}

# Moderation Configuration File
resource "local_file" "moderation_config" {
  count    = var.enable_moderation ? 1 : 0
  filename = "${var.config_path}/matrix-moderation.yaml"

  content = <<-EOT
# Matrix Moderation Configuration

moderation:
  enabled: true
  
  # Content Filtering
  content_filters:
    enabled: ${var.content_filtering_enabled}
    action: ${var.content_filter_action}  # "warn", "redact", or "ban"
    patterns:
%{for pattern in var.content_filter_patterns~}
      - pattern: "${pattern}"
%{endfor~}
  
  # Rate Limiting
  rate_limits:
    messages_per_minute: ${var.rate_limit_messages_per_minute}
    action: ${var.rate_limit_action}  # "warn", "mute", or "kick"
  
  # Audit Logging
  audit_logging:
    enabled: ${var.audit_logging_enabled}
    retention_days: ${var.audit_retention_days}
    events:
      - m.room.message
      - m.room.member
      - m.room.topic
      - m.room.avatar
      - m.room.history_visibility
      - m.room.power_levels

EOT

  lifecycle {
    ignore_changes_all = true
  }
}

# Retention Purge Job (Kubernetes CronJob if using K8s, or Docker scheduled task)
resource "docker_container" "retention_purge_job" {
  count = var.enable_retention_purge_job && !var.use_kubernetes ? 1 : 0

  name  = "matrix-retention-purge"
  image = "matrixdotorg/synapse-admin:latest"

  networks_advanced {
    name = var.docker_network_id
  }

  env = [
    "SYNAPSE_SERVER=${var.homeserver_url}",
    "SYNAPSE_ADMIN_TOKEN=${var.admin_bot_token}",
  ]

  # Schedule via docker restart policy with cron-like behavior handled by host system
  restart_policy {
    condition = "unless-stopped"
  }

  labels = {
    "app"    = "matrix-retention-purge"
    "module" = "matrix-governance"
  }

  lifecycle {
    ignore_changes = [image, restart_policy]
  }
}

# Output: Admin Bot Status
output "admin_bot_container_id" {
  value       = try(docker_container.matrix_admin_bot[0].id, null)
  description = "Container ID of the Matrix admin bot"
}

output "audit_schema_created" {
  value       = try(postgresql_schema.audit_logging[0].name != "", false)
  description = "Whether the audit schema was created"
}
