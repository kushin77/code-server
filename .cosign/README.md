# Cosign Image Signing & Verification

## Overview

This directory contains the public cosign key for verifying container image signatures. All production images are signed with the corresponding private key stored in GitHub Secrets.

## Key Setup (One-Time, Already Done)

```bash
# Generate keypair (on secure machine)
cosign generate-key-pair --kms none

# Store in GitHub Secrets:
# COSIGN_KEY      = contents of cosign.key (private)
# COSIGN_PASSWORD = password for cosign.key  
# COSIGN_PUBLIC_KEY = contents of cosign.pub
```

## Verification

Verify image signature:
```bash
# Using public key from this directory
cosign verify \
  --key .cosign/cosign.pub \
  192.168.168.31:8443/code-server/code-server:main-abc123
```

## Deployment Integration

The CI/CD pipeline (`dagger-cicd-pipeline.yml`) automatically:
1. Signs every pushed image with cosign
2. Attests SBOM to the image
3. Verifies signature before production deployment
4. Fails deploy if signature verification fails

## SLSA L2 Compliance

This implementation provides:
- ✅ Signed provenance (cosign signatures)
- ✅ SBOM attestation (syft + cosign)
- ✅ Pinned base images (by digest in Dockerfile)
- ✅ Reproducible builds (BuildKit caching)
- ✅ Automated verification (pre-deploy checks)

## References

- cosign: https://docs.sigstore.dev/cosign/overview/
- SLSA: https://slsa.dev/spec/v1/levels
