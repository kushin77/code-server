# Service Accounts for Phase 2 Service-to-Service Authentication
# These should be created in Google Secret Manager and loaded at deployment time

# =============================================================================
# 1. API Server (Internal Service)
# =============================================================================
# Purpose: Internal API service that other services call for data/commands
# Credentials stored in: projects/gcp-eiq/secrets/service-account-api-server

SERVICE_ACCOUNT_API_SERVER_ID="api-server@code-server-enterprise.iam.gserviceaccount.com"
SERVICE_ACCOUNT_API_SERVER_SECRET="$(gsm_get_secret service-account-api-server/client-secret)"

# OAuth2 client credentials for token acquisition
OAUTH2_CREDENTIAL_API_SERVER_CLIENT_ID="api-server-service-account"
OAUTH2_CREDENTIAL_API_SERVER_CLIENT_SECRET="${SERVICE_ACCOUNT_API_SERVER_SECRET}"

# =============================================================================
# 2. Code-Server Internal (code-server → API calls)
# =============================================================================
# Purpose: code-server as a client calling internal APIs
# Credentials stored in: projects/gcp-eiq/secrets/service-account-code-server-internal

SERVICE_ACCOUNT_CODE_SERVER_INTERNAL_ID="code-server-internal@code-server-enterprise.iam.gserviceaccount.com"
SERVICE_ACCOUNT_CODE_SERVER_INTERNAL_SECRET="$(gsm_get_secret service-account-code-server-internal/client-secret)"

OAUTH2_CREDENTIAL_CODE_SERVER_CLIENT_ID="code-server-internal-service-account"
OAUTH2_CREDENTIAL_CODE_SERVER_CLIENT_SECRET="${SERVICE_ACCOUNT_CODE_SERVER_INTERNAL_SECRET}"

# =============================================================================
# 3. GitHub Actions (External CI/CD)
# =============================================================================
# Purpose: GitHub Actions workflows authenticate and trigger deployments
# Credentials stored in: projects/gcp-eiq/secrets/service-account-github-actions

SERVICE_ACCOUNT_GITHUB_ACTIONS_ID="github-actions@code-server-enterprise.iam.gserviceaccount.com"
SERVICE_ACCOUNT_GITHUB_ACTIONS_SECRET="$(gsm_get_secret service-account-github-actions/client-secret)"

OAUTH2_CREDENTIAL_GITHUB_ACTIONS_CLIENT_ID="github-actions-service-account"
OAUTH2_CREDENTIAL_GITHUB_ACTIONS_CLIENT_SECRET="${SERVICE_ACCOUNT_GITHUB_ACTIONS_SECRET}"

# GitHub Actions can also use native OIDC federation (preferred)
# See: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
GITHUB_ACTIONS_OIDC_ISSUER="https://ide.kushnir.cloud"
GITHUB_ACTIONS_OIDC_SUBJECT_PREFIX="repo:kushin77/code-server"

# =============================================================================
# 4. Kubernetes ServiceAccounts
# =============================================================================
# Purpose: Kubernetes pods authenticate to code-server-enterprise services
# ServiceAccounts get automatic token mount, but need OIDC federation setup

KUBERNETES_OIDC_ISSUER="https://ide.kushnir.cloud"
KUBERNETES_SERVICEACCOUNT_NAMESPACE="default"
KUBERNETES_SERVICEACCOUNT_NAMES="code-server-operator,deployment-service,monitoring-agent"

# =============================================================================
# Service Account Provisioning Script
# =============================================================================

# Create service accounts in Google Cloud Console:
# 1. Go to Service Accounts page: https://console.cloud.google.com/iam-admin/serviceaccounts
# 2. Create 4 service accounts with roles:
#    - api-server@code-server-enterprise.iam.gserviceaccount.com
#    - code-server-internal@code-server-enterprise.iam.gserviceaccount.com
#    - github-actions@code-server-enterprise.iam.gserviceaccount.com
#    - kubernetes@code-server-enterprise.iam.gserviceaccount.com

# 3. For each service account:
#    a. Create a key (JSON format)
#    b. Store in Google Secret Manager:
#       gcloud secrets create service-account-<name>/client-secret --data-file=<key.json>
#    c. Update IAM roles:
#       - roles/iam.serviceAccountUser
#       - roles/iam.serviceAccountTokenCreator

# 4. For GitHub Actions:
#    a. Enable Workload Identity federation
#    b. Configure GitHub as identity provider
#    c. Map repo:kushin77/code-server:* to service account

# 5. For Kubernetes:
#    a. Enable Workload Identity
#    b. Create ServiceAccounts with annotations
#    c. Bind ServiceAccounts to Google service accounts

# =============================================================================
# Usage Examples
# =============================================================================

# Example 1: code-server acquiring a token
# POST /oauth2/token
# Content-Type: application/x-www-form-urlencoded
# 
# grant_type=client_credentials
# client_id=code-server-internal-service-account
# client_secret=<SECRET_FROM_GSM>
# scope=openid email groups

# Example 2: Using token in API request
# GET /api/services/code-server/status
# Authorization: Bearer <JWT_TOKEN>

# Example 3: GitHub Actions using OIDC
# - No static credentials needed
# - Use ${{ secrets.GITHUB_TOKEN }} or custom OIDC flow
# - Token automatically validated via GitHub issuer

# =============================================================================
# Docker Compose Integration
# =============================================================================

# Add to docker-compose.yml services that need service accounts:
#
# code-server:
#   environment:
#     SERVICE_ACCOUNT_CLIENT_ID: "${OAUTH2_CREDENTIAL_CODE_SERVER_CLIENT_ID}"
#     SERVICE_ACCOUNT_CLIENT_SECRET: "${OAUTH2_CREDENTIAL_CODE_SERVER_CLIENT_SECRET}"
#
# api-server:
#   environment:
#     SERVICE_ACCOUNT_CLIENT_ID: "${OAUTH2_CREDENTIAL_API_SERVER_CLIENT_ID}"
#     SERVICE_ACCOUNT_CLIENT_SECRET: "${OAUTH2_CREDENTIAL_API_SERVER_CLIENT_SECRET}"
