# ════════════════════════════════════════════════════════════════════════════
# Terraform Variables — Development Configuration
# ════════════════════════════════════════════════════════════════════════════
# THIS FILE IS IN .gitignore — DO NOT COMMIT PRODUCTION SECRETS
#
# For production deployment:
#   1. Generate real secrets: openssl rand -base64 32
#   2. Store in Google Secret Manager
#   3. Fetch real secrets: ./scripts/fetch-gsm-secrets.sh
#   4. Or set TF_VAR_* environment variables
# ════════════════════════════════════════════════════════════════════════════

# Service Configuration
domain                 = "ide.kushnir.cloud"
code_server_password   = "enterprise-secure-password-min8-chars"
workspace_path         = "./workspace"
enable_workspace_mount = true

# Docker Configuration
docker_host    = "unix:///var/run/docker.sock"
docker_context = "desktop-linux"

# ─────────────────────────────────────────────────────────────────────────────
# SECRETS — Development Test Values (production sources from GSM)
# ─────────────────────────────────────────────────────────────────────────────

# Google OAuth2 credentials (from GCP Console)
google_client_id     = "dev-test-client-id"
google_client_secret = "dev-test-client-secret"

# oauth2-proxy Session Encryption (CRITICAL: Generate new for production)
# Generate: openssl rand -base64 32
oauth2_proxy_cookie_secret = "dev-test-cookie-secret-base64-encoded="

# GitHub Personal Access Token (optional, for higher API rate limits)
github_token = ""

# Ollama Configuration
ollama_num_threads = 4
ollama_num_gpu     = 0 # Set to 1+ if GPU available and desired
ollama_model       = "llama2"
