variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "apex_domain" {
  description = "Apex domain (e.g. kushnir.cloud)"
  type        = string
}

variable "allowed_emails" {
  description = "List of email addresses allowed to authenticate via Cloudflare Access"
  type        = list(string)
}

variable "google_client_id" {
  description = "Google OAuth2 client ID for Cloudflare Access IdP"
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth2 client secret for Cloudflare Access IdP"
  type        = string
  sensitive   = true
}

variable "deploy_host_ip" {
  description = "IP of the deploy host — used for localhost bypass rule"
  type        = string
  default     = ""
}

variable "warp_device_posture_id" {
  description = "Cloudflare WARP device posture integration ID. Set to enforce WARP enrollment check. Leave empty to skip posture check."
  type        = string
  default     = ""
}

variable "logpush_r2_bucket" {
  description = "Cloudflare R2 bucket name for Access audit log Logpush. Leave empty to skip Logpush configuration."
  type        = string
  default     = ""
}
