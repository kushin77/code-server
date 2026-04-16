#!/usr/bin/env bash
# setup-git-credentials.sh
# One-time idempotent setup: wire git to fetch GitHub PAT from GCP Secret Manager.
#
# Run on EVERY host that needs to push/pull from GitHub:
#   sudo bash scripts/setup-git-credentials.sh
#
# What it does:
#   1. Validates gcloud auth (prompts to login if expired)
#   2. Creates/updates the GSM secret prod-github-token (prompts for PAT if missing)
#   3. Installs git-credential-gsm to /usr/local/bin/
#   4. Removes hardcoded [url ...insteadOf] and credential.helper=store from ~/.gitconfig
#   5. Configures: credential.helper = gsm  (GSM-backed, no plaintext)
#   6. Verifies git can authenticate against github.com
#
# Environment:
#   GSM_PROJECT       GCP project (default: gcp-eiq)
#   GSM_SECRET_NAME   Secret name  (default: prod-github-token)
#   GITHUB_PAT        PAT to store (if not already in GSM); prompted if unset
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly GSM_PROJECT="${GSM_PROJECT:-gcp-eiq}"
readonly GSM_SECRET_NAME="${GSM_SECRET_NAME:-prod-github-token}"
readonly CREDENTIAL_HELPER_BIN="/usr/local/bin/git-credential-gsm"
readonly CREDENTIAL_HELPER_SRC="${SCRIPT_DIR}/git-credential-gsm"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
log()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
die()  { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── 1. Verify prerequisites ───────────────────────────────────────────────────
log "Checking prerequisites..."
command -v gcloud >/dev/null 2>&1 || die "gcloud not found. Install Google Cloud SDK first."
command -v git    >/dev/null 2>&1 || die "git not found."

# ── 2. Refresh gcloud auth ────────────────────────────────────────────────────
log "Checking gcloud authentication (project: ${GSM_PROJECT})..."
if ! CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet auth print-access-token \
        --project="$GSM_PROJECT" >/dev/null 2>&1; then
    warn "gcloud auth token expired or missing."
    echo "  → Running: gcloud auth login --update-adc"
    gcloud auth login --update-adc
fi
log "gcloud auth OK ($(gcloud config get-value account 2>/dev/null))"

# ── 3. Ensure GSM secret exists ───────────────────────────────────────────────
log "Checking GSM secret ${GSM_PROJECT}/${GSM_SECRET_NAME}..."
EXISTING_TOKEN=""
if EXISTING_TOKEN=$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet \
        secrets versions access latest \
        --secret="$GSM_SECRET_NAME" \
        --project="$GSM_PROJECT" 2>/dev/null); then
    log "Secret already exists in GSM — no update needed."
else
    warn "Secret not found in GSM. Creating it now."

    if [[ -z "${GITHUB_PAT:-}" ]]; then
        # Check if a PAT is currently hardcoded in gitconfig (extract for migration)
        HARDCODED_PAT=$(git config --global --get-regexp 'url\..*insteadOf' 2>/dev/null \
            | grep github.com \
            | sed -n 's|url\.\(https://\)\(.*\):x-oauth-basic@github\.com/.*|\2|p' \
            | head -1 || true)

        if [[ -n "$HARDCODED_PAT" ]]; then
            warn "Detected hardcoded PAT in ~/.gitconfig — migrating to GSM."
            GITHUB_PAT="$HARDCODED_PAT"
        else
            echo ""
            echo "Enter your GitHub Personal Access Token (scope: repo, read:org):"
            echo -n "PAT: "
            read -rs GITHUB_PAT
            echo ""
        fi
    fi

    [[ -z "$GITHUB_PAT" ]] && die "GITHUB_PAT is empty — cannot create GSM secret."

    # Create secret or add a new version if it already exists structurally
    if gcloud secrets describe "$GSM_SECRET_NAME" --project="$GSM_PROJECT" >/dev/null 2>&1; then
        echo -n "$GITHUB_PAT" | \
            gcloud secrets versions add "$GSM_SECRET_NAME" \
                --project="$GSM_PROJECT" \
                --data-file=-
        log "Added new version to existing secret ${GSM_SECRET_NAME}."
    else
        echo -n "$GITHUB_PAT" | \
            gcloud secrets create "$GSM_SECRET_NAME" \
                --project="$GSM_PROJECT" \
                --replication-policy="automatic" \
                --data-file=-
        log "Created secret ${GSM_SECRET_NAME} in project ${GSM_PROJECT}."
    fi
fi

# ── 4. Install credential helper binary ───────────────────────────────────────
log "Installing git-credential-gsm to ${CREDENTIAL_HELPER_BIN}..."
[[ -f "$CREDENTIAL_HELPER_SRC" ]] || die "Source not found: ${CREDENTIAL_HELPER_SRC}"

if [[ "$(id -u)" -eq 0 ]]; then
    install -m 755 "$CREDENTIAL_HELPER_SRC" "$CREDENTIAL_HELPER_BIN"
else
    sudo install -m 755 "$CREDENTIAL_HELPER_SRC" "$CREDENTIAL_HELPER_BIN"
fi
log "Installed: ${CREDENTIAL_HELPER_BIN}"

# ── 5. Clean up ~/.gitconfig ──────────────────────────────────────────────────
log "Cleaning ~/.gitconfig..."

# Remove ALL hardcoded [url "https://<token>:x-oauth-basic@github.com/"] sections
GITCONFIG="$HOME/.gitconfig"
if [[ -f "$GITCONFIG" ]]; then
    # Build a sed script: remove all [url "...@github.com..."] stanzas
    # and their insteadOf lines (multi-line pattern — use Python for safety)
    python3 - "$GITCONFIG" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Remove [url "https://<token>@github.com/"] blocks (the PAT-embedding pattern)
cleaned = re.sub(
    r'\[url "https://[^"]*@github\.com[^"]*"\][^\[]*',
    '',
    content,
    flags=re.DOTALL
)

# Remove bare 'helper = store' lines (insecure plain-text storage)
cleaned = re.sub(r'\s*helper\s*=\s*store\s*\n', '\n', cleaned)

with open(path, 'w') as f:
    f.write(cleaned)

print("  ~/.gitconfig cleaned")
PYEOF
fi

# ── 6. Set GSM-backed credential helper ───────────────────────────────────────
# Remove any previously set credential.helper for github.com
git config --global --unset credential.helper 2>/dev/null || true

# Set global helper to gsm (our new binary)
git config --global credential.helper gsm

# Disable plaintext store helper explicitly for github.com
git config --global credential.https://github.com.helper gsm

log "git credential.helper set to: gsm"

# ── 7. Verify ─────────────────────────────────────────────────────────────────
log "Verifying git auth against github.com..."
if git ls-remote https://github.com/kushin77/code-server.git HEAD >/dev/null 2>&1; then
    log "✓ git auth verified — can reach github.com/kushin77/code-server"
else
    warn "git ls-remote failed. Check that the PAT has 'repo' scope and is valid."
    echo "  Manual test: git ls-remote https://github.com/kushin77/code-server.git HEAD"
    exit 1
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN} Git credential setup complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo "  Source of truth : GSM ${GSM_PROJECT}/${GSM_SECRET_NAME}"
echo "  Credential helper: git-credential-gsm (${CREDENTIAL_HELPER_BIN})"
echo "  Plaintext storage: REMOVED"
echo "  Hardcoded URL    : REMOVED"
echo ""
echo "  To rotate the PAT:"
echo "    1. Create new PAT at https://github.com/settings/tokens"
echo "    2. echo -n '<new-pat>' | gcloud secrets versions add ${GSM_SECRET_NAME} \\"
echo "         --project=${GSM_PROJECT} --data-file=-"
echo "    3. No changes needed to gitconfig or deploy scripts"
echo ""
