#!/bin/bash
# scripts/setup-supply-chain-security.sh
# Setup cosign image signing + SBOM generation + vulnerability scanning
# SLSA L2 supply chain integrity configuration

set -euo pipefail

LOG_FILE="/tmp/supply-chain-setup-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $*" | tee -a "$LOG_FILE"
    exit 1
}

# =============================================================================
# 1. INSTALL SUPPLY CHAIN TOOLS
# =============================================================================

install_tools() {
    log "Installing supply chain security tools..."
    
    # Install cosign (container image signing)
    which cosign &>/dev/null || {
        log "Installing cosign v2.0.0..."
        curl -sSL https://github.com/sigstore/cosign/releases/download/v2.0.0/cosign-linux-amd64 -o /tmp/cosign
        chmod +x /tmp/cosign
        sudo mv /tmp/cosign /usr/local/bin/cosign
        log "✓ cosign v2.0.0 installed"
    }
    
    # Install syft (SBOM generation)
    which syft &>/dev/null || {
        log "Installing syft v0.85.0..."
        curl -sSL https://github.com/anchore/syft/releases/download/v0.85.0/syft_0.85.0_linux_amd64.tar.gz -o /tmp/syft.tar.gz
        tar -xzf /tmp/syft.tar.gz -C /tmp
        sudo mv /tmp/syft /usr/local/bin/syft
        log "✓ syft v0.85.0 installed"
    }
    
    # Install grype (vulnerability scanning)
    which grype &>/dev/null || {
        log "Installing grype v0.74.0..."
        curl -sSL https://github.com/anchore/grype/releases/download/v0.74.0/grype_0.74.0_linux_amd64.tar.gz -o /tmp/grype.tar.gz
        tar -xzf /tmp/grype.tar.gz -C /tmp
        sudo mv /tmp/grype /usr/local/bin/grype
        log "✓ grype v0.74.0 installed"
    }
    
    # Install trivy (image scanning - for CI/CD)
    which trivy &>/dev/null || {
        log "Installing trivy v0.48.0..."
        curl -sSL https://github.com/aquasecurity/trivy/releases/download/v0.48.0/trivy_0.48.0_Linux-64bit.tar.gz -o /tmp/trivy.tar.gz
        tar -xzf /tmp/trivy.tar.gz -C /tmp
        sudo mv /tmp/trivy /usr/local/bin/trivy
        log "✓ trivy v0.48.0 installed"
    }
    
    log "✓ All supply chain tools installed"
}

# =============================================================================
# 2. GENERATE COSIGN KEYPAIR
# =============================================================================

setup_cosign_keys() {
    log "Setting up cosign keypair..."
    
    COSIGN_DIR="${HOME}/.cosign"
    mkdir -p "$COSIGN_DIR"
    
    if [ -f "$COSIGN_DIR/cosign.key" ]; then
        log "⚠️ cosign.key already exists, skipping generation"
        return
    fi
    
    # Generate keypair (no password for CI/CD automation, production should use HSM)
    log "Generating cosign keypair..."
    cosign generate-key-pair --kms none 2>&1 | tee -a "$LOG_FILE"
    
    # Keys are saved as:
    # - cosign.key (private key)
    # - cosign.pub (public key)
    
    if [ -f "cosign.key" ]; then
        mv cosign.key "$COSIGN_DIR/"
        mv cosign.pub "$COSIGN_DIR/"
        chmod 600 "$COSIGN_DIR/cosign.key"
        chmod 644 "$COSIGN_DIR/cosign.pub"
        log "✓ Keypair generated and stored in $COSIGN_DIR"
    else
        error "Failed to generate cosign keypair"
    fi
}

# =============================================================================
# 3. VERIFY COSIGN SETUP
# =============================================================================

verify_cosign() {
    log "Verifying cosign setup..."
    
    COSIGN_DIR="${HOME}/.cosign"
    
    [ -f "$COSIGN_DIR/cosign.key" ] || error "cosign.key not found"
    [ -f "$COSIGN_DIR/cosign.pub" ] || error "cosign.pub not found"
    
    log "✓ Cosign keypair verified"
}

# =============================================================================
# 4. CREATE COSIGN CONFIG
# =============================================================================

setup_cosign_config() {
    log "Creating cosign configuration..."
    
    COSIGN_CONFIG="${HOME}/.cosign/cosign.config.yaml"
    
    cat > "$COSIGN_CONFIG" << 'EOF'
# Cosign Configuration
# Container image signing configuration

sigstores:
  # Example: Sigstore public good instance (default)
  # - name: sigstore
  #   uri: https://sigstore.dev
  #   keyless: true
  #   use_identity: true
  #   use_timestamp_server: true

registries:
  # Local registry (if applicable)
  # - registry: localhost:5000
  #   keyless: false
  #   secrets: /root/.cosign/registry-secret.json

# Verification settings
verification:
  # Require signatures for all images
  require_signature: false
  # Allow insecure registries (dev only)
  insecure: false
  # Certificate verification
  verify_cert_chain: true
EOF

    log "✓ Cosign configuration created at $COSIGN_CONFIG"
}

# =============================================================================
# 5. GENERATE SBOM FOR TEST IMAGE
# =============================================================================

generate_sbom() {
    log "Generating SBOM for test image..."
    
    # Example: Generate SBOM for a local image
    TEST_IMAGE="alpine:latest"
    SBOM_FILE="/tmp/sbom-${TEST_IMAGE//\//-}.json"
    
    log "Pulling test image: $TEST_IMAGE"
    docker pull "$TEST_IMAGE" 2>&1 | tail -5
    
    log "Generating SBOM..."
    syft "$TEST_IMAGE" -o json > "$SBOM_FILE"
    
    log "✓ SBOM generated at $SBOM_FILE"
    log "SBOM Summary:"
    jq '.artifacts | length' "$SBOM_FILE" | xargs echo "  Total artifacts:"
}

# =============================================================================
# 6. VERIFY SBOM CONTENT
# =============================================================================

verify_sbom() {
    log "Verifying SBOM content..."
    
    SBOM_FILE="/tmp/sbom-alpine-latest.json"
    
    if [ -f "$SBOM_FILE" ]; then
        log "SBOM Structure:"
        jq 'keys' "$SBOM_FILE" | head -10
        log "✓ SBOM verified"
    else
        error "SBOM file not found: $SBOM_FILE"
    fi
}

# =============================================================================
# 7. CONFIGURE SUPPLY CHAIN IN CI/CD
# =============================================================================

create_ci_integration() {
    log "Creating CI/CD integration guidance..."
    
    cat > /tmp/supply-chain-ci-steps.md << 'EOF'
# Supply Chain Integration in CI/CD

## GitHub Actions Workflow Steps

### 1. Sign Container Image
```yaml
- name: Sign container image
  env:
    COSIGN_KEY: ${{ secrets.COSIGN_KEY }}
    COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
  run: |
    cosign sign --key /path/to/cosign.key \
      --docker-media-types \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

### 2. Generate SBOM
```yaml
- name: Generate SBOM
  run: |
    syft ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
      -o json > sbom.json
    syft ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
      -o spdx > sbom.spdx
```

### 3. Scan for Vulnerabilities
```yaml
- name: Scan image for vulnerabilities
  run: |
    grype ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
      --fail-on critical \
      -o json > grype-results.json
```

### 4. Verify Signature Before Deployment
```yaml
- name: Verify image signature
  env:
    COSIGN_KEY: ${{ secrets.COSIGN_PUBLIC_KEY }}
  run: |
    cosign verify --key /path/to/cosign.pub \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

### 5. Upload Artifacts for Compliance
```yaml
- name: Upload SBOM to artifact registry
  run: |
    cosign attach sbom ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
      --sbom sbom.json
```

## Pre-Deployment Checklist
- ✅ Image is signed (cosign verify passes)
- ✅ SBOM is generated (syft output valid)
- ✅ No critical vulnerabilities (grype --fail-on critical passed)
- ✅ Base image is trusted (base image signature verified)
- ✅ Build provenance is recorded (SLSA L2 compatible)

## Post-Deployment Verification
```bash
# Verify deployed image signature
cosign verify --key cosign.pub $REGISTRY/$IMAGE:$TAG

# Check SBOM attached to image
cosign sbom $REGISTRY/$IMAGE:$TAG

# List all signatures
cosign tree $REGISTRY/$IMAGE:$TAG
```
EOF

    log "✓ CI/CD integration guidance created at /tmp/supply-chain-ci-steps.md"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "Starting Supply Chain Security Setup..."
    log "Log: $LOG_FILE"
    
    install_tools
    setup_cosign_keys
    verify_cosign
    setup_cosign_config
    generate_sbom
    verify_sbom
    create_ci_integration
    
    log ""
    log "✅ Supply Chain Security Setup Complete!"
    log ""
    log "Next Steps:"
    log "1. Store cosign private key securely:"
    log "   gh secret set COSIGN_KEY < ~/.cosign/cosign.key"
    log "2. Store cosign password:"
    log "   gh secret set COSIGN_PASSWORD < <password-file>"
    log "3. Store public key for verification:"
    log "   gh secret set COSIGN_PUBLIC_KEY < ~/.cosign/cosign.pub"
    log "4. Update CI/CD workflow with signing steps"
    log "5. Add SBOM generation and vulnerability scanning to CI"
}

main "$@"
