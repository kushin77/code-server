# Dependency Health Audit Report

**Generated**: 2026-04-20T01:17:17Z

## Summary

This report documents:
- CVE vulnerabilities found in dependencies
- License compliance status
- Outdated packages requiring remediation
- Recommendations for resolution

---

## Table of Contents

1. [Node.js (pnpm) Dependencies](#nodejs-dependencies)
2. [Python Dependencies](#python-dependencies)
3. [Container Base Images](#container-base-images)
4. [License Compliance](#license-compliance)
5. [Outdated Packages](#outdated-packages)
6. [Remediation Backlog](#remediation-backlog)

---

## Node.js Dependencies

### pnpm audit output

```
[SKIPPED] pnpm not available in CI environment
```

## Python Dependencies

### pip-audit output

```
[SKIPPED] pip-audit not available
```

## Container Base Images

### /mnt/c/code-server-enterprise/apps/session-broker/Dockerfile

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/docker/haproxy/Dockerfile

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/Dockerfile

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/Dockerfile.caddy

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/Dockerfile.code-server

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/Dockerfile.ssh-proxy

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/Dockerfile.token-microservice

```
[SKIPPED] Trivy not available
```

### /mnt/c/code-server-enterprise/terraform/modules/keepalived/build/Dockerfile

```
[SKIPPED] Trivy not available
```

## License Compliance

### Restricted Licenses Check

Scanning for restricted licenses: GPL AGPL LGPL SSPL BUSL Copyleft

```
[SKIPPED] license-checker not available (install: npm install -g license-checker)
```

## Outdated Packages

### npm outdated

```
```

## Remediation Backlog

### Action Items

- [ ] Review critical CVEs and apply patches
- [ ] Resolve high-severity vulnerabilities within 30 days
- [ ] Evaluate and replace restricted-license dependencies
- [ ] Update packages marked as outdated
- [ ] Schedule dependency updates in sprint planning

### Policy Enforcement

The following CI gates are now active:
1. **CVE Severity Gate**: Fail on Critical CVEs, block on High until triaged
2. **License Gate**: Fail on GPL, AGPL, SSPL, BUSL in production dependencies
3. **Outdated Package Gate**: Warn on packages >2 minor versions behind latest

