# Terraform Users Management - IaC-Based User Configuration

variable "allowed_users" {
  description = "Map of allowed IDE users with roles and permissions"
  type = map(object({
    email    = string
    role     = string  # viewer, developer, architect, admin
    disabled = optional(bool, false)
  }))

  # ✅ Default users (override in terraform.tfvars)
  default = {
    akushnir = {
      email    = "akushnir@bioenergystrategies.com"
      role     = "admin"
      disabled = false
    }
  }

  validation {
    condition = alltrue([
      for user in var.allowed_users : contains(["viewer", "developer", "architect", "admin"], user.role)
    ])
    error_message = "Role must be one of: viewer, developer, architect, admin"
  }

  validation {
    condition = alltrue([
      for user in var.allowed_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", user.email))
    ])
    error_message = "All user emails must be valid"
  }
}

# ✅ Generate allowed-emails.txt from Terraform
# This is the OAuth2 allowlist - generated from var.allowed_users
resource "local_file" "allowed_emails" {
  filename = "${path.module}/../allowed-emails.txt"
  content = join("\n", concat(
    # Add enabled users
    [for user in var.allowed_users : user.email if !user.disabled],
    # Ensure file ends with newline
    [""]
  ))

  file_permission = "0644"

  # ✅ Detect drift - if file edited outside Terraform, aler
  lifecycle {
    ignore_changes = [] # Don't ignore - we WANT to detect drif
  }
}

# ✅ Generate per-user settings directory structure
resource "local_file" "user_workspace_readme" {
  for_each = {
    for name, user in var.allowed_users : name => user
    if !user.disabled
  }

  filename = "${path.module}/../workspaces/${each.key}/README.md"
  content = <<-EO
# Development Workspace

Welcome, ${each.value.email}!

## Your Configuration
- **Role**: ${each.value.role}
- **Email**: ${each.value.email}
- **Status**: Active

## Settings Applied
See `config/user-settings/${each.key}/` for detailed settings.

## Next Steps
1. Open any file to start editing (if role allows)
2. Use Ctrl+Shift+P for command palette
3. Save with Ctrl+S (auto-formatting enabled if developer role)

## Restrictions
${each.value.role == "viewer" ? "- ❌ Code editing disabled (read-only mode)" : ""}
${contains(["viewer", "developer", "architect"], each.value.role) ? "- ❌ Terminal access disabled" : ""}
${contains(["viewer", "architect"], each.value.role) ? "- ❌ File download disabled" : ""}

For role details, see: IDE_SECURITY_AND_USER_MANAGEMENT.md
EO

  file_permission = "0644"

  depends_on = [
    local_file.allowed_emails
  ]
}

# ✅ Generate per-user metadata
resource "local_file" "user_metadata" {
  for_each = {
    for name, user in var.allowed_users : name => user
    if !user.disabled
  }

  filename = "${path.module}/../config/user-settings/${each.key}/user-metadata.json"
  content = jsonencode({
    user_id        = each.key
    email          = each.value.email
    role           = each.value.role
    date_created   = timestamp()
    status         = "active"
    managed_by     = "terraform"
  })

  file_permission = "0644"

  depends_on = [
    local_file.allowed_emails
  ]
}

# ✅ Link role settings to user settings
resource "null_resource" "user_settings_symlink" {
  for_each = {
    for name, user in var.allowed_users : name => user
    if !user.disabled
  }

  provisioner "local-exec" {
    # For each user, link their role template to their settings
    command = <<-EO
      mkdir -p "${path.module}/../config/user-settings/${each.key}"

      # Link to role template
      if [ -f "${path.module}/../config/role-settings/${each.value.role}-profile.json" ]; then
        ln -sf "../../role-settings/${each.value.role}-profile.json" \
          "${path.module}/../config/user-settings/${each.key}/settings.json" || true
      fi
    EO
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    local_file.user_metadata
  ]
}

# ✅ Output user configuration for audit/debugging
output "configured_users" {
  description = "Currently configured IDE users"
  value = {
    for name, user in var.allowed_users :
    name => {
      email    = user.email
      role     = user.role
      disabled = user.disabled
      workspace = "${path.module}/../workspaces/${name}"
      settings = "${path.module}/../config/user-settings/${name}"
    }
  }
}

output "allowed_emails_file" {
  description = "Path to generated OAuth2 allowlist file"
  value       = local_file.allowed_emails.filename
}

output "user_count" {
  description = "Total number of enabled users"
  value       = length([for u in var.allowed_users : u if !u.disabled])
}
