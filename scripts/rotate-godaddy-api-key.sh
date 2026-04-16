#!/bin/bash
################################################################################
# Script: Rotate GoDaddy API Key (Quarterly)
# Purpose: Implement secure API key rotation for GoDaddy registrar access
# Owner: Platform Engineering
# Reference: Issue #347 - GoDaddy Registrar Hardening
# Usage: bash scripts/rotate-godaddy-api-key.sh
################################################################################

set -e

# Configuration
ROTATION_INTERVAL_DAYS=90
VAULT_PATH="secret/godaddy"
BACKUP_DIR="/root/.backup/godaddy-keys"
LOG_FILE="/var/log/godaddy-api-rotation.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Helper functions
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

success() {
  echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
  echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
  echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

################################################################################
# Function: Check if rotation is needed
################################################################################
check_rotation_needed() {
  log "Checking if API key rotation is due..."

  # Try to get last rotation date from Vault
  if ! command -v vault &> /dev/null; then
    error "HashiCorp Vault CLI not found. Cannot check rotation status."
    error "Either install Vault or manually check: vault kv get secret/godaddy"
    return 2
  fi

  # Get last rotation date
  LAST_ROTATION=$(vault kv get -field=rotation_date "$VAULT_PATH" 2>/dev/null || echo "")
  
  if [ -z "$LAST_ROTATION" ]; then
    warning "No previous rotation date found in Vault. Treating as first rotation."
    return 0  # Needs rotation
  fi

  # Calculate days since last rotation
  LAST_ROTATION_EPOCH=$(date -d "$LAST_ROTATION" +%s)
  CURRENT_EPOCH=$(date +%s)
  DAYS_SINCE_ROTATION=$(( (CURRENT_EPOCH - LAST_ROTATION_EPOCH) / 86400 ))

  log "Last API key rotation: $LAST_ROTATION ($DAYS_SINCE_ROTATION days ago)"

  if [ $DAYS_SINCE_ROTATION -ge $ROTATION_INTERVAL_DAYS ]; then
    success "API key rotation is DUE (${DAYS_SINCE_ROTATION}d >= ${ROTATION_INTERVAL_DAYS}d)"
    return 0
  else
    DAYS_UNTIL_DUE=$(( ROTATION_INTERVAL_DAYS - DAYS_SINCE_ROTATION ))
    warning "API key rotation not yet due ($DAYS_UNTIL_DUE days remaining)"
    return 1
  fi
}

################################################################################
# Function: Backup current key
################################################################################
backup_current_key() {
  log "Backing up current API key..."

  # Get current key from Vault
  CURRENT_KEY=$(vault kv get -field=api_key "$VAULT_PATH" 2>/dev/null || echo "")
  
  if [ -z "$CURRENT_KEY" ]; then
    warning "No current key found in Vault. Skipping backup."
    return 0
  fi

  # Create backup file with timestamp
  BACKUP_FILE="$BACKUP_DIR/godaddy-api-key-$(date +%Y%m%d-%H%M%S).txt"
  echo "$CURRENT_KEY" > "$BACKUP_FILE"
  chmod 600 "$BACKUP_FILE"
  
  success "Current key backed up to: $BACKUP_FILE"
}

################################################################################
# Function: Generate new API key (manual or automated)
################################################################################
generate_new_key() {
  log "Generating new GoDaddy API key..."
  
  echo ""
  echo "========================================================================="
  echo "MANUAL STEP REQUIRED: Create new API key in GoDaddy Developer Console"
  echo "========================================================================="
  echo ""
  echo "Steps:"
  echo "1. Log into developer.godaddy.com with your GoDaddy account"
  echo "2. Navigate: API Keys → Create Key"
  echo "3. Configure:"
  echo "   - Name: code-server-enterprise-rotation-$(date +%Y%m%d)"
  echo "   - Permissions: 'domains' (domains only, not all)"
  echo "   - Scope: kushin.cloud (specific domain)"
  echo "   - Rate limit: 100 requests/minute"
  echo "4. Copy the API Key and API Secret"
  echo ""
  echo "========================================================================="
  echo ""
  
  read -p "Enter new GoDaddy API KEY: " NEW_API_KEY
  read -sp "Enter new GoDaddy API SECRET: " NEW_API_SECRET
  echo ""

  if [ -z "$NEW_API_KEY" ] || [ -z "$NEW_API_SECRET" ]; then
    error "API key or secret is empty"
    return 1
  fi

  export NEW_API_KEY
  export NEW_API_SECRET
  return 0
}

################################################################################
# Function: Test new API key
################################################################################
test_new_key() {
  log "Testing new API key with read-only operation..."

  # Make read-only API call to test key
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: sso-key $NEW_API_KEY:$NEW_API_SECRET" \
    https://api.godaddy.com/v1/domains/kushin.cloud)

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)

  if [ "$HTTP_CODE" == "200" ]; then
    success "API key test passed (HTTP $HTTP_CODE)"
    return 0
  else
    error "API key test failed (HTTP $HTTP_CODE)"
    error "Response: $(echo "$RESPONSE" | head -1)"
    return 1
  fi
}

################################################################################
# Function: Update Vault
################################################################################
update_vault() {
  log "Updating HashiCorp Vault with new API key..."

  if ! command -v vault &> /dev/null; then
    error "HashiCorp Vault CLI not found. Cannot update Vault."
    error "Manual step: Update Vault with new key"
    error "Command: vault kv put secret/godaddy api_key='$NEW_API_KEY' api_secret='$NEW_API_SECRET' rotation_date='$(date -u +%Y-%m-%d)'"
    return 1
  fi

  vault kv put "$VAULT_PATH" \
    api_key="$NEW_API_KEY" \
    api_secret="$NEW_API_SECRET" \
    rotation_date="$(date -u +%Y-%m-%d)" \
    rotated_by="$(whoami)" \
    rotation_timestamp="$(date -u +%s)" || {
    error "Failed to update Vault"
    return 1
  }

  success "Vault updated with new API key"
}

################################################################################
# Function: Update .env file (if local)
################################################################################
update_env_file() {
  log "Checking for .env file to update..."

  if [ ! -f ".env" ]; then
    warning ".env file not found in current directory"
    warning "Manual step: Update GODADDY_API_TOKEN in .env file on deployment servers"
    warning "Location: /root/.env or wherever .env is stored on 192.168.168.31"
    return 0
  fi

  # Backup .env
  cp .env ".env.backup.$(date +%Y%m%d-%H%M%S)"
  
  # Update API token
  if grep -q "^GODADDY_API_TOKEN=" .env; then
    sed -i "s/^GODADDY_API_TOKEN=.*/GODADDY_API_TOKEN=$NEW_API_KEY/" .env
    success "Updated GODADDY_API_TOKEN in .env"
  else
    warning "GODADDY_API_TOKEN not found in .env. Add manually:"
    warning "  GODADDY_API_TOKEN=$NEW_API_KEY"
  fi

  if grep -q "^GODADDY_API_SECRET=" .env; then
    sed -i "s/^GODADDY_API_SECRET=.*/GODADDY_API_SECRET=$NEW_API_SECRET/" .env
    success "Updated GODADDY_API_SECRET in .env"
  fi
}

################################################################################
# Function: Delete old key in GoDaddy
################################################################################
delete_old_key() {
  log "Deleting old API key from GoDaddy..."

  echo ""
  echo "========================================================================="
  echo "MANUAL STEP REQUIRED: Delete old API key from GoDaddy Developer Console"
  echo "========================================================================="
  echo ""
  echo "Steps:"
  echo "1. Log into developer.godaddy.com"
  echo "2. Navigate: API Keys"
  echo "3. Find the OLD API key (not the one you just created)"
  echo "4. Click 'Delete' and confirm"
  echo ""
  echo "This prevents the old key from being used if compromised."
  echo ""
  echo "========================================================================="
  echo ""

  read -p "Press Enter once you've deleted the old key in GoDaddy... "
  success "Old key deletion acknowledged"
}

################################################################################
# Function: Schedule next rotation
################################################################################
schedule_next_rotation() {
  log "Next rotation scheduled for: $(date -d '+90 days' '+%Y-%m-%d')"

  if command -v systemctl &> /dev/null; then
    warning "To schedule automatic rotation, add to crontab:"
    warning "  0 9 * * * /path/to/scripts/rotate-godaddy-api-key.sh"
  fi

  success "Rotation complete and logged"
}

################################################################################
# Main Execution
################################################################################
main() {
  log "=========================================="
  log "GoDaddy API Key Rotation Script"
  log "=========================================="
  log "Started at: $(date)"

  # Check if rotation is needed
  if ! check_rotation_needed; then
    if [ $? -eq 1 ]; then
      log "API key rotation not yet due. Exiting."
      exit 0
    fi
    # If check_rotation_needed returns 2, it's a configuration error
    error "Unable to determine rotation status"
    exit 1
  fi

  # Backup current key
  if ! backup_current_key; then
    error "Failed to backup current key"
    exit 1
  fi

  # Generate new key
  if ! generate_new_key; then
    error "Failed to get new API key"
    exit 1
  fi

  # Test new key
  if ! test_new_key; then
    error "New API key test failed. Not proceeding with rotation."
    error "Verify the key is correct and try again."
    exit 1
  fi

  # Update Vault
  if ! update_vault; then
    error "Failed to update Vault. Aborting rotation."
    exit 1
  fi

  # Update .env file (if present)
  update_env_file

  # Delete old key
  delete_old_key

  # Schedule next rotation
  schedule_next_rotation

  log "=========================================="
  log "API Key Rotation Completed Successfully"
  log "Next rotation due: $(date -d '+90 days' '+%Y-%m-%d')"
  log "=========================================="
}

# Run main function
main "$@"
exit $?
