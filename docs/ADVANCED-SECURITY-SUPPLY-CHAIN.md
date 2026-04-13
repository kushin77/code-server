# Phase 13: Advanced Security & Supply Chain

## Overview

Phase 13 implements enterprise-grade supply chain security, container image security, vulnerability management, and compliance automation. This builds on Phase 10's foundational security and adds FAANG-level supply chain protection.

**Objectives:**
- ✅ Software Bill of Materials (SBOM) generation and tracking
- ✅ Container image scanning and vulnerability management
- ✅ Image signing and signature verification
- ✅ Artifact attestation and provenance tracking
- ✅ Automated dependency vulnerability scanning
- ✅ Compliance automation (CIS, NIST, PCI-DSS)

---

## 1. Software Bill of Materials (SBOM) Generation

### 1.1 CycloneDX SBOM Generation

```bash
#!/bin/bash
# security/generate-sbom.sh

set -e

SERVICE=${1:-code-server}
VERSION=${2:-$(git describe --tags)}

echo "=== Generating SBOM for $SERVICE:$VERSION ==="

# Install syft if not present
if ! command -v syft &> /dev/null; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi

# Generate SBOM in CycloneDX format (most enterprise-friendly)
syft $SERVICE:$VERSION \
  -o cyclonedx-json \
  --file sbom-$SERVICE-$VERSION.json

# Generate SBOM in SPDX format
syft $SERVICE:$VERSION \
  -o spdx-json \
  --file sbom-$SERVICE-$VERSION-spdx.json

# Generate summary report
echo ""
echo "=== SBOM Summary ==="

jq '[.components[]] | {
  total: length,
  by_type: (group_by(.type) | map({
    type: .[0].type,
    count: length
  })),
  by_license: (group_by(.licenses[0].license.name // "UNKNOWN") | map({
    license: .[0].licenses[0].license.name // "UNKNOWN",
    count: length
  }))
}' sbom-$SERVICE-$VERSION.json

echo ""
echo "✅ SBOM files generated:"
echo "  - sbom-$SERVICE-$VERSION.json (CycloneDX)"
echo "  - sbom-$SERVICE-$VERSION-spdx.json (SPDX)"

# Upload to artifact repository
echo ""
echo "Uploading to artifact repository..."
curl -u $ARTIFACTORY_USER:$ARTIFACTORY_TOKEN \
  -T sbom-$SERVICE-$VERSION.json \
  "https://artifactory.internal/sbom/$SERVICE/$VERSION/"

echo "✅ SBOM uploaded successfully"
```

### 1.2 SBOM Validation & Compliance Checking

```python
# security/validate-sbom.py

#!/usr/bin/env python3

import json
import sys
from collections import defaultdict

RESTRICTED_LICENSES = {
    'GPL-2.0',
    'GPL-3.0',
    'AGPL-3.0',
    'SSPL-1.0'
}

CRITICAL_VULNERABILITIES = {
    'log4j': 'CVE-2021-44228',
    'struts': 'CVE-2017-5645',
    'jackson': 'CVE-2017-15095'
}

def validate_sbom(sbom_file):
    """Validate SBOM for compliance and security issues"""
    
    with open(sbom_file) as f:
        sbom = json.load(f)
    
    issues = []
    warnings = []
    
    # Validate SBOM structure
    if 'version' not in sbom or 'serialNumber' not in sbom:
        issues.append('Invalid SBOM: missing required fields')
        return issues, warnings
    
    # Check for license compliance
    license_counts = defaultdict(int)
    for component in sbom.get('components', []):
        licenses = component.get('licenses', [])
        for lic in licenses:
            license_name = lic.get('license', {}).get('name', 'UNKNOWN')
            license_counts[license_name] += 1
            
            if license_name in RESTRICTED_LICENSES:
                issues.append(
                    f"RESTRICTED LICENSE: {component['name']} uses {license_name}"
                )
    
    # Check for known vulnerable components
    for component in sbom.get('components', []):
        name = component.get('name', '')
        version = component.get('version', '')
        
        for vuln_name, cve in CRITICAL_VULNERABILITIES.items():
            if vuln_name.lower() in name.lower():
                issues.append(
                    f"CRITICAL VULNERABILITY: {name}:{version} may have {cve}"
                )
    
    # Check for outdated components (>1 year old)
    # This is simplified; real implementation would check release dates
    
    # Check for unpatched dependencies
    unpatched = component.get('purl', '').startswith('pkg:npm/') and \
                not component.get('externalReferences', [])
    
    if unpatched:
        warnings.append(f"Component {component.get('name')} may lack vulnerability info")
    
    return issues, warnings

def print_report(sbom_file):
    """Print validation report"""
    
    print(f"\n=== SBOM Compliance Report: {sbom_file} ===\n")
    
    issues, warnings = validate_sbom(sbom_file)
    
    if issues:
        print(f"❌ CRITICAL ISSUES ({len(issues)}):")
        for issue in issues:
            print(f"   - {issue}")
    else:
        print("✅ No critical issues found")
    
    if warnings:
        print(f"\n⚠️  WARNINGS ({len(warnings)}):")
        for warning in warnings:
            print(f"   - {warning}")
    else:
        print("\n✅ No warnings")
    
    # Exit with error if critical issues
    return len(issues) == 0

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: validate-sbom.py <sbom-file.json>")
        sys.exit(1)
    
    success = print_report(sys.argv[1])
    sys.exit(0 if success else 1)
```

---

## 2. Container Image Security

### 2.1 Image Scanning with Grype

```bash
#!/bin/bash
# security/scan-image.sh

set -e

IMAGE=${1}
SEVERITY_THRESHOLD=${2:-HIGH}

echo "=== Container Image Security Scan ==="
echo "Image: $IMAGE"
echo "Severity Threshold: $SEVERITY_THRESHOLD"
echo ""

# Install grype if not present
if ! command -v grype &> /dev/null; then
  curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
fi

# Scan image
echo "Scanning for vulnerabilities..."
grype $IMAGE \
  -o json \
  --file scan-results.json \
  --fail-on $SEVERITY_THRESHOLD

# Parse results
TOTAL_VULNS=$(jq '.matches | length' scan-results.json)
CRITICAL=$(jq '[.matches[] | select(.vulnerability.severity=="Critical")] | length' scan-results.json)
HIGH=$(jq '[.matches[] | select(.vulnerability.severity=="High")] | length' scan-results.json)
MEDIUM=$(jq '[.matches[] | select(.vulnerability.severity=="Medium")] | length' scan-results.json)

echo ""
echo "=== Scan Results ==="
echo "Total Vulnerabilities: $TOTAL_VULNS"
echo "  🔴 Critical: $CRITICAL"
echo "  🟠 High: $HIGH"
echo "  🟡 Medium: $MEDIUM"

# Detailed critical/high findings
if [ $((CRITICAL + HIGH)) -gt 0 ]; then
  echo ""
  echo "=== Critical/High Vulnerabilities ==="
  jq '.matches[] | select(.vulnerability.severity=="Critical" or .vulnerability.severity=="High")' scan-results.json | \
  jq -r '[
    "ID: \(.vulnerability.id)",
    "Package: \(.artifact.name):\(.artifact.version)",
    "Severity: \(.vulnerability.severity)",
    "Description: \(.vulnerability.description)",
    ""
  ] | join("\n")' 
fi

# Generate SARIF report for integration with GitHub/GitLab
grype $IMAGE \
  -o sarif \
  --file scan-results.sarif

echo ""
echo "✅ Scan complete. Results saved:"
echo "  - scan-results.json"
echo "  - scan-results.sarif (for CI/CD integration)"
```

### 2.2 Image Scanning in CI/CD Pipeline

```yaml
# .github/workflows/container-security-scan.yml

name: Container Security Scan

on:
  push:
    branches:
      - main
      - develop
  pull_request:

jobs:
  scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
      
    steps:
    - uses: actions/checkout@v4
    
    - name: Build Docker image
      run: |
        docker build -t code-server:${{ github.sha }} \
          -f Dockerfile .
    
    - name: Install Grype
      uses: anchore/scan-action@v3
      id: scan
      with:
        image: code-server:${{ github.sha }}
        fail-build: true
        severity-cutoff: high
    
    - name: Upload Sarif to GitHub
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: ${{ steps.scan.outputs.sarif }}
    
    - name: Check Scan Results
      if: ${{ steps.scan.outcome == 'failure' }}
      run: |
        echo "❌ Container scan failed due to vulnerabilities"
        exit 1
```

---

## 3. Image Signing & Verification

### 3.1 Cosign Image Signing

```bash
#!/bin/bash
# security/sign-image.sh

set -e

IMAGE=${1}

echo "=== Signing Container Image ==="
echo "Image: $IMAGE"

# Install cosign if not present
if ! command -v cosign &> /dev/null; then
  curl -sSfL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 \
    -o /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign
fi

# Generate signing key if it doesn't exist
if [ ! -f cosign.key ]; then
  echo "Generating new signing key..."
  cosign generate-key-pair
fi

# Sign image
echo "Signing image with Cosign..."
cosign sign --key cosign.key \
  -a git.commit=$GITHUB_SHA \
  -a git.branch=$GITHUB_REF \
  -a build.timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  $IMAGE

# Verify signature
echo ""
echo "Verifying signature..."
cosign verify --key cosign.pub $IMAGE

# Verify with OIDC (GitHub Actions)
echo ""
echo "Verifying with OIDC..."
cosign verify \
  --certificate-identity-regexp 'https://github.com/kushin77/eiq-linkedin/\.github/workflows' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  $IMAGE

echo ""
echo "✅ Image signed and verified successfully"
```

### 3.2 Admission Controller for Image Verification

```yaml
# kubernetes/base/image-verification-policy.yaml

apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-verification
webhooks:
- name: verify-image-signature.security.io
  clientConfig:
    service:
      name: webhook-service
      namespace: kube-system
      path: "/verify"
    caBundle: LS0tLS1CRUdJTi... # base64 encoded CA cert
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
    scope: "Namespaced"
  failurePolicy: Fail
  sideEffects: None
  admissionReviewVersions: ["v1"]
  namespaceSelector:
    matchLabels:
      image-verification: enabled

---
# Example Pod with image verification
apiVersion: v1
kind: Pod
metadata:
  name: verified-pod
  namespace: default
  labels:
    image-verification: enabled
spec:
  containers:
  - name: app
    image: code-server:sha256-abc123@sha256:xyz789
    # ^ Must be signed with trusted key
    imagePullPolicy: Always
```

---

## 4. Artifact Attestation & Provenance

### 4.1 In-Toto Provenance Tracking

```bash
#!/bin/bash
# security/generate-attestation.sh

set -e

ARTIFACT=${1}
BUILD_ID=${2:-local-$(date +%s)}

echo "=== Generating Artifact Attestation ==="
echo "Artifact: $ARTIFACT"
echo "Build ID: $BUILD_ID"

# Install in-toto if not present
if ! command -v in-toto-run &> /dev/null; then
  pip install in-toto
fi

# Create link metadata for the build
in-toto-run --step-name build \
  --materials $ARTIFACT \
  --products $ARTIFACT \
  --key-and-gpg-keyid build-key.gpg \
  -- docker build -t code-server .

# Sign the metadata
gpg --detach-sign build.link

# Create attestation artifact
cat > ${ARTIFACT}.attestation.json << EOF
{
  "artifact": "$ARTIFACT",
  "build_id": "$BUILD_ID",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "builder": "$(git config user.email)",
  "commit": "$(git rev-parse HEAD)",
  "branch": "$(git rev-parse --abbrev-ref HEAD)",
  "ci_workflow": "$GITHUB_WORKFLOW",
  "ci_run_id": "$GITHUB_RUN_ID",
  "provenance": {
    "builder_id": "https://github.com/kushin77/eiq-linkedin/.github/workflows",
    "source_uri": "git+https://github.com/kushin77/eiq-linkedin.git@$(git rev-parse HEAD)",
    "invocation": {
      "config_source": {
        "uri": ".github/workflows/build.yml",
        "digest": {
          "sha256": "$(sha256sum .github/workflows/build.yml | cut -d' ' -f1)"
        }
      },
      "parameters": {},
      "environment": {
        "GitHub-Hosted": "ubuntu-latest"
      }
    },
    "build_type": "https://github.com/actions/setup-node/build@1",
    "build_config": {
      "steps": [
        "action: build-artifact",
        "action: scan-image",
        "action: sign-image",
        "action: push-registry"
      ]
    }
  },
  "slsa_version": "0.1.0"
}
EOF

echo "✅ Attestation generated: ${ARTIFACT}.attestation.json"
```

### 4.2 SLSA Build Level Compliance

```bash
#!/bin/bash
# security/validate-slsa-compliance.sh

set -e

echo "=== SLSA Build Level Compliance Check ==="

SLSA_LEVEL=0

# SLSA Level 1: Provenance just provenance that artifact is built by CI/CD
if [ -f "$ARTIFACT.attestation.json" ]; then
  SLSA_LEVEL=1
  echo "✅ Level 1: Provenance available"
fi

# SLSA Level 2: Requires signed provenance
if [ -f "$ARTIFACT.attestation.json" ] && \
   [ -f "$ARTIFACT.attestation.json.sig" ]; then
  SLSA_LEVEL=2
  echo "✅ Level 2: Signed provenance available"
fi

# SLSA Level 3: Requires builder isolation + source/history preservation
if [ -n "$GITHUB_ACTIONS" ] && \
   [ -n "$GITHUB_RUN_ID" ] && \
   [ -f "$ARTIFACT.attestation.json" ] && \
   grep -q "GitHub-Hosted" "$ARTIFACT.attestation.json"; then
  SLSA_LEVEL=3
  echo "✅ Level 3: Isolated build environment + GitHub Actions"
fi

# SLSA Level 4: Requires hardened builder + high-confidence source verification
if [ "$SLSA_LEVEL" -ge 3 ] && \
   grep -q '"hardened_runner": true' "$ARTIFACT.attestation.json" && \
   grep -q '"source_uri": "git+https' "$ARTIFACT.attestation.json"; then
  SLSA_LEVEL=4
  echo "✅ Level 4: Hardened builder + verified source"
fi

echo ""
echo "Current SLSA Build Level: $SLSA_LEVEL"
echo "Target: Level 4 (minimum for production)"

[ $SLSA_LEVEL -ge 3 ] && echo "✅ PASSED" || echo "❌ FAILED"
```

---

## 5. Dependency Vulnerability Scanning

### 5.1 Automated Dependency Scanning

```bash
#!/bin/bash
# security/scan-dependencies.sh

set -e

echo "=== Dependency Vulnerability Scanning ==="

# Node.js dependencies
if [ -f "package.json" ]; then
  echo ""
  echo "Scanning Node.js dependencies..."
  npm audit --audit-level=moderate
  npm audit fix --audit-level=moderate
fi

# Python dependencies
if [ -f "requirements.txt" ]; then
  echo ""
  echo "Scanning Python dependencies..."
  pip install safety
  safety check --file requirements.txt --json > python-vulns.json
fi

# System dependencies (apt)
if [ -f "Dockerfile" ]; then
  echo ""
  echo "Scanning Dockerfile for vulnerable base images..."
  
  BASE_IMAGE=$(grep '^FROM' Dockerfile | awk '{print $2}' | head -1)
  echo "Base image: $BASE_IMAGE"
  
  grype $BASE_IMAGE -o json | jq '.matches[] | select(.vulnerability.severity=="Critical" or .vulnerability.severity=="High")'
fi

# Go dependencies
if [ -f "go.mod" ]; then
  echo ""
  echo "Scanning Go dependencies..."
  go list -json -m all | nancy sleuth -output json > go-vulns.json
fi

echo ""
echo "✅ Dependency scan complete"
```

### 5.2 GitHub Security Alerts Integration

```yaml
# .github/workflows/dependency-scan.yml

name: Dependency Scan

on:
  push:
    branches: [main]
    paths: ['package.json', 'package-lock.json', 'requirements.txt', 'go.mod']
  pull_request:

jobs:
  scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Run npm audit
      run: npm audit --json > npm-audit.json || true
    
    - name: Upload to security dashboard
      uses: actions/upload-artifact@v3
      with:
        name: vulnerability-reports
        path: |
          npm-audit.json
          python-vulns.json
          go-vulns.json
    
    - name: Fail if critical vulnerabilities
      run: |
        if jq '.metadata.vulnerabilities | select(.critical > 0)' npm-audit.json; then
          echo "❌ Critical vulnerabilities detected"
          exit 1
        fi
```

---

## 6. Compliance Automation

### 6.1 CIS Kubernetes Compliance Checker

```bash
#!/bin/bash
# security/check-cis-compliance.sh

set -e

echo "=== CIS Kubernetes Benchmark Compliance ==="

# Install kube-bench if not present
if ! command -v kube-bench &> /dev/null; then
  curl -L https://github.com/aquasecurity/kube-bench/releases/latest/download/kube-bench_linux_amd64.tar.gz | tar xz
  sudo mv kube-bench /usr/local/bin
fi

# Run CIS benchmark
echo "Running CIS Kubernetes Benchmark..."
kube-bench run --json > cis-benchmark-results.json

# Extract results
PASSED=$(jq '[.[] | .tests[] | .results[] | select(.status=="PASS")] | length' cis-benchmark-results.json)
FAILED=$(jq '[.[] | .tests[] | .results[] | select(.status=="FAIL")] | length' cis-benchmark-results.json)
WARN=$(jq '[.[] | .tests[] | .results[] | select(.status=="WARN")] | length' cis-benchmark-results.json)

echo ""
echo "=== CIS Compliance Results ==="
echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"
echo "⚠️  Warnings: $WARN"

# Generate report
SCORE=$(echo "scale=2; $PASSED * 100 / ($PASSED + $FAILED + $WARN)" | bc)
echo ""
echo "Compliance Score: ${SCORE}%"

# Alert on failures
if [ $FAILED -gt 0 ]; then
  echo ""
  echo "Failed Controls:"
  jq -r '.[] | .tests[] | .results[] | select(.status=="FAIL") | "  - \(.test_number): \(.test_desc)"' cis-benchmark-results.json
fi

[ $FAILED -eq 0 ] && echo "" && echo "✅ All critical controls passed" || exit 1
```

### 6.2 NIST 800-53 Compliance Checklist

```yaml
# security/nist-800-53-compliance.yaml

nist_controls:
  AC-2:
    title: Account Management
    requirement: Unique user accounts with multifactor authentication
    implementation:
      - RBAC with service accounts per namespace
      - OAuth2 proxy for human users
      - MFA enforced for cluster access
    verification:
      - kubectl get serviceaccounts -A
      - Check OAuth2 configuration
  
  AC-3:
    title: Access Enforcement
    requirement: Role-based access control enforced
    implementation:
      - Kubernetes RBAC policies
      - NetworkPolicy for pod-to-pod access
      - Pod Security Standards
    verification:
      - kubectl get roles,rolebindings -A
      - kubectl get networkpolicies -A
  
  AU-2:
    title: Audit and Accountability
    requirement: Audit logs for all security-relevant events
    implementation:
      - Kubernetes audit logging to Elasticsearch
      - etcd audit trail
      - Application logging to Loki
    verification:
      - Check /var/log/kubernetes/audit.log
      - Query Elasticsearch for audit events
  
  AU-12:
    title: Audit Record Generation
    requirement: Audit system generates records for auditable events
    implementation:
      - API server audit policy configured
      - Pod-level logging enabled
      - Container runtime audit
    verification:
      - kube-apiserver --audit-log-path=...
      - containerd audit plugin enabled
  
  CA-6:
    title: Security Assessment
    requirement: Regular security assessments and scanning
    implementation:
      - Weekly vulnerability scans (grype)
      - Monthly penetration testing
      - Continuous compliance checks (kube-bench)
    verification:
      - Run security/scan-image.sh
      - Review cis-benchmark-results.json
  
  CM-2:
    title: Baseline Configuration
    requirement: Baseline configuration documented and maintained
    implementation:
      - Infrastructure as Code (Terraform)
      - GitOps for all changes
      - Configuration management system
    verification:
      - terraform.tfstate validated
      - Git history for all IaC changes
  
  IA-4:
    title: Identifier Management
    requirement: Unique identifiers for individuals
    implementation:
      - Service account names per pod
      - User identity provider (OAuth2)
      - Audit trail of all identities
    verification:
      - kubectl logs with identity attributes
      - OAuth2 logs for user actions
  
  SC-4:
    title: Information Flow Enforcement
    requirement: Denied or controlled information flow
    implementation:
      - NetworkPolicy enforcement
      - Service mesh (optional)
      - Firewall rules
    verification:
      - kubectl describe networkpolicy
      - iptables rules on nodes
  
  SC-7:
    title: Boundary Protection
    requirement: Physical/logical boundaries enforced
    implementation:
      - Network segmentation
      - Private cluster endpoints
      - VPC isolation
    verification:
      - Security group rules
      - Cluster endpoint configuration

compliance_check_frequency:
  critical_controls: daily
  major_controls: weekly
  minor_controls: monthly

reporting:
  format: NIST_SP_800-53_Continuous_Monitoring
  recipients:
    - security-team@company.com
    - ciso@company.com
  frequency: monthly
```

---

## 7. Policy-as-Code (OPA/Gatekeeper)

### 7.1 OPA Policies for Security

```rego
# security/opa-policies/require-image-signature.rego

package kubernetes.admission

deny[msg] {
    input.request.kind.kind == "Pod"
    image := input.request.object.spec.containers[_].image
    not startswith(image, "sha256:")
    msg := sprintf("Image must be signed and use digest: %v", [image])
}

deny[msg] {
    input.request.kind.kind == "Pod"
    image := input.request.object.spec.containers[_].image
    not contains(image, "@sha256:")
    msg := sprintf("Image must use digest format (image@sha256:...): %v", [image])
}
```

### 7.2 Gatekeeper Deployment

```yaml
# kubernetes/base/gatekeeper.yaml

apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-security-labels
spec:
  match:
    kinds:
    - apiGroups: ["*"]
      kinds: ["Pod", "Deployment", "StatefulSet"]
  parameters:
    labels: ["security-scan", "image-signature-verified"]

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockPrivilegedContainers
metadata:
  name: block-privileged-containers
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: require-readiness-probes
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    probes: ["readinessProbe"]
```

---

## 8. Security Incident Response

### 8.1 Incident Detection Workflow

```yaml
# .github/workflows/security-incident-detection.yml

name: Security Incident Detection

on:
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes
  workflow_dispatch:

jobs:
  detect-incidents:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Scan for suspicious activity
      run: |
        # Check for exposed secrets
        git log -p HEAD~100..HEAD | grep -E '(password|api_key|token|secret)' > /tmp/secrets-found.txt || true
        
        if [ -s /tmp/secrets-found.txt ]; then
          echo "🚨 CRITICAL: Secrets found in commit history!"
          exit 1
        fi
    
    - name: Check for unauthorized changes
      run: |
        # Flag any changes to security policies
        git diff HEAD~1 security/ | grep '^-' | head -20
    
    - name: Create incident if needed
      if: failure()
      uses: actions/github-script@v6
      with:
        script: |
          github.rest.issues.create({
            owner: context.repo.owner,
            repo: context.repo.repo,
            title: '🚨 [AUTO] Security Incident: Suspicious Activity Detected',
            body: 'Automated scan detected potential security issue. Review immediately.',
            labels: ['security', 'incident', 'critical']
          })
```

---

## 9. Monitoring Dashboard

```json
{
  "dashboard": {
    "title": "Security & Supply Chain Dashboard",
    "tags": ["security", "compliance"],
    "panels": [
      {
        "title": "Image Scan Status",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(grype_vulnerabilities_total{severity='Critical'})"
          }
        ]
      },
      {
        "title": "Compliance Score",
        "type": "gauge",
        "targets": [
          {
            "expr": "kube_bench_compliance_score"
          }
        ]
      },
      {
        "title": "Signed Images %",
        "type": "gauge",
        "targets": [
          {
            "expr": "image_signatures_verified / image_total * 100"
          }
        ]
      },
      {
        "title": "Vulnerabilities Trend",
        "type": "timeseries",
        "targets": [
          {
            "expr": "grype_vulnerabilities_total by (severity)"
          }
        ]
      },
      {
        "title": "SBOM Generation Status",
        "type": "table",
        "targets": [
          {
            "expr": "sbom_generated{timestamp=~'.*'}"
          }
        ]
      }
    ]
  }
}
```

---

## 10. Success Criteria

- ✅ All images signed with Cosign
- ✅ SBOM generated for every release
- ✅ Zero critical vulnerabilities in containers
- ✅ CIS Kubernetes compliance score >95%
- ✅ NIST 800-53 controls automated + monitored
- ✅ Image signature validation enforced
- ✅ Supply chain provenance tracked end-to-end
- ✅ Compliance reports automated monthly

---

## Next Steps

1. Implement SBOM generation in build pipeline
2. Deploy Grype for image scanning
3. Setup Cosign for image signing
4. Deploy Gatekeeper with security policies
5. Run CIS compliance check
6. Create compliance dashboard
7. Begin **Phase 14: Multi-Environment Consistency & GitOps**

