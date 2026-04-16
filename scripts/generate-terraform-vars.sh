#!/usr/bin/env bash
# scripts/generate-terraform-vars.sh
# P2 #366: Generate terraform.tfvars from inventory environment variables
# Usage: ./scripts/generate-terraform-vars.sh [output-file]

set -euo pipefail

OUTPUT_FILE="${1:-.terraform.tfvars}"

# Validate required environment variables are loaded
required_vars=(
  "DEPLOY_HOST"
  "REPLICA_HOST"
  "VIRTUAL_IP"
  "GATEWAY_IP"
  "STORAGE_IP"
  "NETWORK_SUBNET"
)

echo "? Generating Terraform variables from inventory..."
echo ""

missing_vars=()
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo "✗ ERROR: Missing required environment variables:"
  printf '  - %s\n' "${missing_vars[@]}"
  echo ""
  echo "? Load from inventory: source .env.inventory"
  exit 1
fi

# Generate terraform.tfvars with inventory values
cat > "$OUTPUT_FILE" << EOF
# Generated from inventory at $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source: .env.inventory
# Do not commit - regenerate via: ./scripts/generate-terraform-vars.sh

# Deployment Hosts
deployment_host = "$DEPLOY_HOST"
replica_host    = "$REPLICA_HOST"
virtual_ip      = "$VIRTUAL_IP"
gateway_ip      = "$GATEWAY_IP"
storage_ip      = "$STORAGE_IP"
network_subnet  = "$NETWORK_SUBNET"

# Vault Configuration
vault_addr = "https://$DEPLOY_HOST:8201"

# Network Configuration
deploy_port    = 22
deploy_user    = "akushnir"
replica_port   = 22
replica_user   = "akushnir"
EOF

echo "✓ Generated: $OUTPUT_FILE"
echo ""
echo "Variables:"
echo "  DEPLOY_HOST:   $DEPLOY_HOST"
echo "  REPLICA_HOST:  $REPLICA_HOST"
echo "  VIRTUAL_IP:    $VIRTUAL_IP"
echo "  GATEWAY_IP:    $GATEWAY_IP"
echo "  STORAGE_IP:    $STORAGE_IP"
echo ""
echo "? Next: terraform plan -var-file=$OUTPUT_FILE"
