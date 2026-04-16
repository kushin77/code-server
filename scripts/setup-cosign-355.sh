#!/bin/bash
# IMPLEMENTATION: #355 Supply Chain Security - Cosign Key Setup
# Timeline: 30 minutes
# Location: Run on secure local machine (not in production)

set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo "SUPPLY CHAIN SECURITY (#355) - COSIGN KEY GENERATION"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check prerequisites
if ! command -v cosign &> /dev/null; then
    echo "⚠ cosign not found. Installing..."
    COSIGN_VERSION="v2.2.3"
    curl -sLo /usr/local/bin/cosign https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64
    chmod +x /usr/local/bin/cosign
    cosign version
fi

echo "✓ cosign installed: $(cosign version 2>&1 | head -1)"
echo ""

# Step 1: Generate keypair
echo "STEP 1: Generate cosign keypair"
echo "────────────────────────────────"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
cosign generate-key-pair --kms none

echo "✓ Generated: cosign.key (private) and cosign.pub (public)"
echo ""

# Step 2: Display public key (can be committed to repo)
echo "STEP 2: Public key (safe to commit to repo)"
echo "────────────────────────────────────────────"
cat cosign.pub
echo ""

# Step 3: Setup instructions for GitHub Secrets
echo "STEP 3: Store in GitHub Secrets"
echo "──────────────────────────────────"
echo "Run these commands:"
echo ""
echo "# Read private key (VERY SENSITIVE)"
echo "gh secret set COSIGN_KEY < cosign.key"
echo ""
echo "# Cosign key password (if you set one)"
echo "gh secret set COSIGN_PASSWORD"
echo "# (enter password when prompted)"
echo ""
echo "# Public key (safe to commit)"
echo "gh secret set COSIGN_PUBLIC_KEY < cosign.pub"
echo ""

# Step 4: Display key material (for manual entry into GitHub Secrets)
echo "STEP 4: Key Material for Manual Entry"
echo "──────────────────────────────────────"
echo ""
echo "--- COSIGN.PUB (can be public, safe to commit) ---"
cat cosign.pub
echo ""
echo "--- END COSIGN.PUB ---"
echo ""

# Prepare for GitHub Actions workflow update
echo "STEP 5: Next Steps"
echo "──────────────────"
echo ""
echo "1. Copy cosign.pub to repo:"
echo "   cp cosign.pub /path/to/code-server-enterprise/"
echo ""
echo "2. Commit public key:"
echo "   git add cosign.pub"
echo "   git commit -m 'chore: Add cosign public key for image verification'"
echo ""
echo "3. Update .github/workflows/dagger-cicd-pipeline.yml:"
echo "   - Pin trivy-action version (remove @master)"
echo "   - Add syft SBOM generation"
echo "   - Add cosign signing step"
echo "   - Add image verification before deploy"
echo ""
echo "4. Test:"
echo "   - Push to GitHub"
echo "   - Watch: GitHub Actions → dagger-cicd-pipeline"
echo "   - Verify: Images signed + SBOM generated"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "✓ KEY GENERATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
