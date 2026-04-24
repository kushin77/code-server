#!/bin/bash
# SSH Key Rotation - Direct Execution (bypasses terminal pager)
# This script is designed to be executed on the production replicas directly

set -euo pipefail

AUDIT_LOG="/tmp/ssh-rotation-$(date +%s).log"

{
  echo "SSH Key Rotation - Executed $(date)"
  
  # Step 1: Backup current key
  if [[ -f ~/.ssh/id_rsa_onprem ]]; then
    cp ~/.ssh/id_rsa_onprem ~/.ssh/id_rsa_onprem.old.$(date +%s)
    echo "✓ Backed up old key"
  fi
  
  # Step 2: Generate new key
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_onprem -N "" -C "kushnir-rotated-$(date +%Y%m%d)" 2>&1 | grep -i 'creating\|your'
  chmod 400 ~/.ssh/id_rsa_onprem
  echo "✓ Generated new SSH key"
  
  # Step 3: Verify new key  
  if [[ -f ~/.ssh/id_rsa_onprem && -f ~/.ssh/id_rsa_onprem.pub ]]; then
    echo "✓ New key pair verified"
    stat -c "Key file: %s bytes, permissions: %a" ~/.ssh/id_rsa_onprem
  fi
  
  echo ""
  echo "SSH Key Rotation Complete on $(hostname)"
  
} | tee "$AUDIT_LOG"

cat "$AUDIT_LOG"
