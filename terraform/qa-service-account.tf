# @file        terraform/qa-service-account.tf
# @module      gcp/iam
# @description QA service account + credentials in Google Secret Manager
#
# Creates:
# - Google Service Account for QA user (qa@kushnir.cloud)
# - Service account key stored in GSM
# - Secret Manager secrets for E2E test credentials
# - Email forwarding from QA account to distribution group
#
# Note: gcp_project_id variable is defined in variables.tf
#

# ============================================================================
# Service Account for QA (simulates qa@kushnir.cloud user)
# ============================================================================

resource "google_service_account" "qa_user" {
  project      = var.gcp_project_id
  account_id   = "qa-user"
  display_name = "QA Service Account"
  description  = "Service account for E2E testing (qa@kushnir.cloud simulation)"
}

# ============================================================================
# Service Account Key (for GSM storage)
# ============================================================================

resource "google_service_account_key" "qa_user_key" {
  service_account_id = google_service_account.qa_user.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# ============================================================================
# Store Credentials in Google Secret Manager
# ============================================================================

# Email credential
resource "google_secret_manager_secret" "qa_user_email" {
  secret_id = "qa-user-email"
  project   = var.gcp_project_id

  replication {
    automatic = true
  }

  labels = {
    managed-by = "terraform"
    component  = "e2e-testing"
  }
}

resource "google_secret_manager_secret_version" "qa_user_email_version" {
  secret      = google_secret_manager_secret.qa_user_email.id
  secret_data = "qa@kushnir.cloud"
}

# Service Account Key (private key JSON)
resource "google_secret_manager_secret" "qa_service_account_key" {
  secret_id = "qa-service-account-key"
  project   = var.gcp_project_id

  replication {
    automatic = true
  }

  labels = {
    managed-by = "terraform"
    component  = "e2e-testing"
  }
}

resource "google_secret_manager_secret_version" "qa_service_account_key_version" {
  secret      = google_secret_manager_secret.qa_service_account_key.id
  secret_data = base64decode(google_service_account_key.qa_user_key.private_key)
}

# ============================================================================
# GitHub Actions Service Account - Grant Access to QA Secrets
# ============================================================================

data "google_service_account" "github_actions" {
  account_id = "github-actions"
  project    = var.gcp_project_id
}

# Grant GitHub Actions access to QA email secret
resource "google_secret_manager_secret_iam_member" "github_actions_qa_email" {
  secret_id = google_secret_manager_secret.qa_user_email.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_service_account.github_actions.email}"
}

# Grant GitHub Actions access to QA service account key
resource "google_secret_manager_secret_iam_member" "github_actions_qa_key" {
  secret_id = google_secret_manager_secret.qa_service_account_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_service_account.github_actions.email}"
}

# ============================================================================
# Service Account Permissions - Read-only access for E2E testing
# ============================================================================

# Grant QA service account ability to authenticate (for testing)
resource "google_project_iam_member" "qa_user_viewer" {
  project = var.gcp_project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.qa_user.email}"
}

# ============================================================================
# Outputs for CI/CD Integration
# ============================================================================

output "qa_user_email" {
  description = "QA service account email"
  value       = google_service_account.qa_user.email
}

output "qa_user_email_secret_id" {
  description = "GSM secret ID for QA email"
  value       = google_secret_manager_secret.qa_user_email.secret_id
}

output "qa_service_account_key_secret_id" {
  description = "GSM secret ID for QA service account key"
  value       = google_secret_manager_secret.qa_service_account_key.secret_id
}

output "github_actions_service_account" {
  description = "GitHub Actions service account email (has access to secrets)"
  value       = data.google_service_account.github_actions.email
}
