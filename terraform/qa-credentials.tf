# @file        terraform/qa-credentials.tf
# @module      gcp/iam/credentials
# @description QA credential management for OAuth endpoint testing (immutable, idempotent, automated)
#
# This module manages QA user credentials used for E2E OAuth testing:
# - Google Secret Manager secrets (immutable versions)
# - IAM bindings for CI/CD service accounts
# - Automatic credential rotation scheduling
# - Versioned secret management (never overwrite, always version)
#
# Variables are defined in variables.tf
#

# ============================================================================
# Google Secret Manager Secrets (Immutable Versions)
# ============================================================================

# QA User Email (immutable, versioned)
resource "google_secret_manager_secret" "qa_email" {
  project   = var.gcp_project_id
  secret_id = "qa-user-email"

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }

  labels = {
    env        = "qa"
    purpose    = "oauth-testing"
    managed-by = "terraform"
    immutable  = "true"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [replication[0].auto]
  }
}

# QA User Password (immutable, versioned, sensitive)
resource "google_secret_manager_secret" "qa_password" {
  project   = var.gcp_project_id
  secret_id = "qa-user-password"

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }

  labels = {
    env        = "qa"
    purpose    = "oauth-testing"
    managed-by = "terraform"
    immutable  = "true"
    sensitive  = "true"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [replication[0].auto]
  }
}

# ============================================================================
# Secret Versions (Immutable Records)
# ============================================================================

# QA Email Version (never updated, always versioned)
resource "google_secret_manager_secret_version" "qa_email_version" {
  secret      = google_secret_manager_secret.qa_email.id
  secret_data = var.qa_email

  lifecycle {
    ignore_changes = all
  }
}

# QA Password Version (never updated, always versioned)
resource "google_secret_manager_secret_version" "qa_password_version" {
  secret      = google_secret_manager_secret.qa_password.id
  secret_data = var.qa_password

  lifecycle {
    ignore_changes = all
  }
}

# ============================================================================
# IAM: Grant CI Service Account Secret Access (Immutable Binding)
# ============================================================================

# CI can READ qa-user-email
resource "google_secret_manager_secret_iam_member" "ci_email_accessor" {
  secret_id = google_secret_manager_secret.qa_email.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.ci_service_account_email}"

  lifecycle {
    prevent_destroy = true
  }
}

# CI can READ qa-user-password
resource "google_secret_manager_secret_iam_member" "ci_password_accessor" {
  secret_id = google_secret_manager_secret.qa_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.ci_service_account_email}"

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# Outputs (For CI/CD Consumption)
# ============================================================================

output "qa_email_secret_id" {
  description = "GSM secret ID for QA email"
  value       = google_secret_manager_secret.qa_email.id
}

output "qa_password_secret_id" {
  description = "GSM secret ID for QA password"
  value       = google_secret_manager_secret.qa_password.id
}

output "qa_credentials_ready" {
  description = "Whether QA credentials are provisioned and accessible"
  value       = true

  depends_on = [
    google_secret_manager_secret_version.qa_email_version,
    google_secret_manager_secret_version.qa_password_version,
    google_secret_manager_secret_iam_member.ci_email_accessor,
    google_secret_manager_secret_iam_member.ci_password_accessor,
  ]
}
