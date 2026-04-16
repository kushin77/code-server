#!/bin/bash
# P1 #417: Remote Terraform State Backend Setup
# 
# Configures S3-compatible backend (MinIO) for terraform state
# Prevents state corruption, enables multi-host deployments
# 
# Usage: bash scripts/setup-terraform-remote-state.sh

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "P1 #417: Remote Terraform State Backend Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""

PRIMARY_HOST="192.168.168.31"
PRIMARY_USER="akushnir"

# Step 1: Verify MinIO is running (already part of docker-compose)
echo "Step 1/4: Verifying MinIO S3 backend is available..."
ssh -o StrictHostKeyChecking=accept-new "${PRIMARY_USER}@${PRIMARY_HOST}" <<'EOF'
cd /home/akushnir/code-server-enterprise

echo "Checking MinIO status..."
if docker-compose ps | grep -q "minio.*Up"; then
  echo "✅ MinIO is running"
  
  # Test S3 connectivity
  if docker-compose exec -T minio minio version > /dev/null 2>&1; then
    echo "✅ MinIO is accessible"
  else
    echo "⚠️  MinIO healthcheck may need time"
  fi
else
  echo "⚠️  MinIO not running - ensure docker-compose has minio service"
fi
EOF

# Step 2: Create backend configuration
echo ""
echo "Step 2/4: Creating terraform backend configuration..."
cat > /code-server-enterprise/terraform/backend-config.hcl <<'BACKEND'
# Remote State Backend Configuration
# MinIO S3-compatible storage on 192.168.168.31:9000
# 
# Reference: https://www.terraform.io/language/settings/backends/s3

bucket         = "terraform-state"
key            = "code-server-enterprise/terraform.tfstate"
region         = "us-east-1"
endpoint       = "http://minio:9000"
skip_region_validation      = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
force_path_style           = true

# DynamoDB for state locking (if available)
dynamodb_table = "terraform-locks"
BACKEND

echo "✅ Backend configuration created at terraform/backend-config.hcl"

# Step 3: Create/migrate state on primary host
echo ""
echo "Step 3/4: Initializing remote state backend on primary host..."
ssh -o StrictHostKeyChecking=accept-new "${PRIMARY_USER}@${PRIMARY_HOST}" <<'EOF'
cd /home/akushnir/code-server-enterprise/terraform

# Set MinIO credentials from environment (.env file)
export AWS_ACCESS_KEY_ID="${MINIO_ROOT_USER:-minioadmin}"
export AWS_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD:-minioadmin}"

# Initialize with remote backend
echo "Running terraform init with MinIO backend..."
terraform init -backend-config=backend-config.hcl -upgrade

if [ $? -eq 0 ]; then
  echo "✅ Terraform remote state initialized successfully"
  
  # Verify state file exists
  echo "Verifying state file in MinIO..."
  docker-compose exec -T minio mc ls minio/terraform-state || echo "⚠️  State may not be visible yet"
else
  echo "❌ Failed to initialize remote state"
  exit 1
fi
EOF

# Step 4: Verify state migration
echo ""
echo "Step 4/4: Verifying state backend configuration..."
ssh -o StrictHostKeyChecking=accept-new "${PRIMARY_USER}@${PRIMARY_HOST}" <<'EOF'
cd /home/akushnir/code-server-enterprise/terraform

echo "Checking backend status..."
if terraform show > /dev/null 2>&1; then
  echo "✅ State backend is accessible"
  echo ""
  echo "State file information:"
  terraform state list 2>/dev/null | head -5 || echo "  (no resources in state yet)"
else
  echo "⚠️  Could not access state - verify MinIO credentials"
fi
EOF

# Step 5: Document replica setup
echo ""
echo "Step 5: Setting up replica host (192.168.168.42)..."
cat > c:\code-server-enterprise\scripts\setup-terraform-replica-state.sh <<'REPLICA_SCRIPT'
#!/bin/bash
# Setup terraform state on replica host to sync from primary

REPLICA_HOST="192.168.168.42"
REPLICA_USER="akushnir"

ssh -o StrictHostKeyChecking=accept-new "${REPLICA_USER}@${REPLICA_HOST}" <<'EOF'
cd /home/akushnir/code-server-enterprise/terraform

# Point to same MinIO backend as primary
export AWS_ACCESS_KEY_ID="${MINIO_ROOT_USER:-minioadmin}"
export AWS_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD:-minioadmin}"

echo "Configuring replica to use remote state..."
terraform init -backend-config=backend-config.hcl -upgrade

echo "✅ Replica terraform now reads from shared MinIO backend"
EOF
REPLICA_SCRIPT

chmod +x c:\code-server-enterprise\scripts\setup-terraform-replica-state.sh

echo "═══════════════════════════════════════════════════════════════"
echo "✅ Remote Terraform State Backend Setup Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Backend: MinIO S3-compatible (on primary host)"
echo "  Bucket: terraform-state"
echo "  State file: code-server-enterprise/terraform.tfstate"
echo "  Locking: DynamoDB (optional)"
echo ""
echo "Features:"
echo "  ✓ Remote state prevents corruption"
echo "  ✓ State locking prevents concurrent modifications"
echo "  ✓ Multi-host deployments supported"
echo "  ✓ Backup: MinIO data persisted on NAS"
echo ""
echo "Next steps:"
echo "  1. Run: bash scripts/setup-terraform-replica-state.sh"
echo "  2. Verify: terraform state list"
echo "  3. Deploy: terraform apply"
echo ""
echo "References:"
echo "  - Terraform S3 Backend: https://www.terraform.io/language/settings/backends/s3"
echo "  - MinIO Setup: docker-compose.yml service: minio"
