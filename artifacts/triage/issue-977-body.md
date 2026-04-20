## Severity: HIGH (3 supply chain vulnerabilities in Dockerfile.code-server)

---

## Finding 1 — Rust installed via `curl | sh` (Dockerfile.code-server:56)

### Evidence
```dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```

### Risk
- `curl | sh` is an OWASP-listed supply chain attack pattern
- If `sh.rustup.rs` is compromised or DNS is hijacked, all new code-server image builds receive malicious code silently
- Builds are non-deterministic: the installed Rust version varies by build date

### Fix
```dockerfile
ARG RUST_VERSION=1.75.0
ARG RUSTUP_SHA256=a3339fb2068a7e92a0e8fbf28a16a6c68e8e89a3fda17c3f5e1a74ca67e7a98e

RUN curl -fO "https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init" \
    && echo "${RUSTUP_SHA256}  rustup-init" | sha256sum -c \
    && chmod +x rustup-init \
    && ./rustup-init -y --default-toolchain "${RUST_VERSION}" --no-modify-path \
    && rm rustup-init
```

---

## Finding 2 — VSIX extensions downloaded from VS Code Marketplace at build time (Dockerfile.code-server:83-88)

### Evidence
```dockerfile
ARG COPILOT_VERSION=1.299.0

RUN curl -fL -o /tmp/github-copilot.vsix.gz \
  "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot/1.295.0/vspackage"
```

**Version mismatch**: `ARG COPILOT_VERSION=1.299.0` but the URL hardcodes `1.295.0`.

### Risk
- Marketplace downloads during build tie build reproducibility to VS Marketplace availability
- A compromised or taken-down extension breaks all new builds
- No checksum verification — a malicious VSIX would be silently accepted
- The version mismatch means the pinned ARG has no effect

### Fix
1. Host VSIX files in the project's NAS or a GCS bucket:
   ```bash
   gsutil cp github-copilot-${COPILOT_VERSION}.vsix gs://vsix-cache/
   ```
2. Download with SHA256 verification in the Dockerfile:
   ```dockerfile
   ARG COPILOT_VSIX_SHA256=<known-good-sha256>
   RUN curl -fL -o /tmp/github-copilot.vsix "gs://vsix-cache/github-copilot-${COPILOT_VERSION}.vsix" \
       && echo "${COPILOT_VSIX_SHA256}  /tmp/github-copilot.vsix" | sha256sum -c
   ```
3. Fix the version mismatch: use `${COPILOT_VERSION}` in the URL

---

## Finding 3 — pip install without hash verification (Dockerfile:17)

### Evidence
```dockerfile
RUN pip3 install --no-cache-dir pre-commit==3.7.1
```

Version is pinned, but the wheel content is not verified. If PyPI is compromised or the package is tampered with, the pinned version check provides no protection.

### Fix
```dockerfile
COPY requirements-ci.txt /tmp/requirements-ci.txt
RUN pip3 install --no-cache-dir --require-hashes -r /tmp/requirements-ci.txt
```

Where `requirements-ci.txt` contains:
```
pre-commit==3.7.1 \
    --hash=sha256:abc123... \
    --hash=sha256:def456...
```
Generate with `pip-compile --generate-hashes`.

---

## Definition of Done
- [ ] Rust install in Dockerfile.code-server uses verified sha256 checksum
- [ ] VSIX extensions downloaded from internal cache (NAS/GCS) with sha256 verification
- [ ] ARG COPILOT_VERSION is actually used in the download URL (fix version mismatch)
- [ ] pip install uses `--require-hashes` with generated requirements file
- [ ] `docker build` is reproducible: same inputs produce same layer hashes
- [ ] `trivy image` scan on new image shows no supply chain CVEs
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
