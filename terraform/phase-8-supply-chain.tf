# Phase 8-B: Supply Chain Security (#355)
# cosign artifact signing, SBOM generation, image verification
# Immutable versions: cosign 2.0.0, syft 0.85.0, grype 0.74.0, trivy 0.48.0

variable "cosign_version" {
  description = "cosign binary version (immutable)"
  type        = string
  default     = "2.0.0"
}

variable "syft_version" {
  description = "syft SBOM generator version (immutable)"
  type        = string
  default     = "0.85.0"
}

variable "grype_version" {
  description = "grype vulnerability scanner (immutable)"
  type        = string
  default     = "0.74.0"
}

variable "trivy_version" {
  description = "Trivy container image scanner (immutable)"
  type        = string
  default     = "0.48.0"
}

# ============================================================================
# Supply Chain Security Configuration
# ============================================================================

resource "local_file" "setup_supply_chain" {
  filename = "${path.module}/../scripts/setup-supply-chain-security.sh"
  content = templatefile("${path.module}/../templates/setup-supply-chain-security.sh.tpl", {
    cosign_version = var.cosign_version
    syft_version   = var.syft_version
    grype_version  = var.grype_version
    trivy_version  = var.trivy_version
  })
}

resource "local_file" "sign_container_images" {
  filename = "${path.module}/../scripts/sign-container-images.sh"
  content = templatefile("${path.module}/../templates/sign-container-images.sh.tpl", {
    registry = "docker.io"
  })
}

resource "local_file" "generate_sbom" {
  filename = "${path.module}/../scripts/generate-sbom.sh"
  content = templatefile("${path.module}/../templates/generate-sbom.sh.tpl", {
    syft_version = var.syft_version
  })
}

resource "local_file" "scan_vulnerabilities" {
  filename = "${path.module}/../scripts/scan-vulnerabilities.sh"
  content = templatefile("${path.module}/../templates/scan-vulnerabilities.sh.tpl", {
    grype_version = var.grype_version
    trivy_version = var.trivy_version
  })
}

resource "local_file" "cicd_signing_pipeline" {
  filename = "${path.module}/../.github/workflows/sign-and-scan.yml"
  content = templatefile("${path.module}/../templates/sign-and-scan.yml.tpl", {
    cosign_version = var.cosign_version
    syft_version   = var.syft_version
  })
}

output "supply_chain_security_config" {
  value = {
    code_signing = {
      tool           = "cosign"
      version        = var.cosign_version
      algorithm      = "ECDSA (p256)"
      key_management = "Vault PKI (Phase 8-A)"
    }
    sbom_generation = {
      tool    = "syft"
      version = var.syft_version
      format  = "SPDX JSON"
      include = [
        "OS packages",
        "Language libraries",
        "Binary dependencies"
      ]
    }
    vulnerability_scanning = {
      tools    = ["grype", "trivy"]
      versions = {
        grype = var.grype_version
        trivy = var.trivy_version
      }
      failure_thresholds = {
        critical = 0
        high     = 1
      }
    }
    artifact_verification = {
      requires_signature = true
      requires_sbom      = true
      verify_before      = "deployment"
    }
    slo_targets = {
      sbom_generation     = "30s per image"
      vulnerability_scan  = "120s per image"
      signature_creation  = "10s per image"
      signature_verify    = "5s per image"
      approval_deadline   = "1h from scan"
    }
  }
}
