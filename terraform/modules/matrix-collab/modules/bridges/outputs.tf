output "slack_bridge_enabled" {
  value       = var.enable_slack_bridge
  description = "Whether Slack bridge is enabled"
}

output "teams_bridge_enabled" {
  value       = var.enable_teams_bridge
  description = "Whether Teams bridge is enabled"
}

output "google_chat_bridge_enabled" {
  value       = var.enable_google_chat_bridge
  description = "Whether Google Chat bridge is enabled"
}
