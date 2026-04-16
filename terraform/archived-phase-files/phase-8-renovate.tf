# Phase 8-B: Renovate Dependency Automation (#358)
# Automated dependency scanning, updates, and security patches
# Immutable: Renovate auto-updates safely, Dependency-check 8.x

variable "renovate_version" {
  description = "Renovate bot version (auto-updated safely)"
  type        = string
  default     = "37.x"
}

variable "dependency_check_version" {
  description = "OWASP Dependency-Check version (immutable)"
  type        = string
  default     = "8.x"
}

# ============================================================================
# Renovate Configuration
# ============================================================================

resource "local_file" "renovate_config" {
  filename = "${path.module}/../.renovaterc"
  content = jsonencode({
    extends = [
      "config:base",
      "schedule:weekly"
    ]
    semanticCommits = "enabled"
    updateTypes = [
      "minor",
      "patch"
    ]
    docker = {
      enabled   = true
      automerge = true
      major = {
        automerge = false
      }
    }
    npm = {
      enabled   = true
      automerge = true
      major = {
        automerge = false
      }
    }
    python = {
      enabled   = true
      automerge = true
    }
    terraform = {
      enabled   = true
      automerge = false
    }
    vulnerabilityAlerts = {
      enabled = true
      labels = [
        "security"
      ]
    }
    packageRules = [
      {
        description = "Disable automerge for major updates"
        matchUpdateTypes = [
          "major"
        ]
        automerge = false
      },
      {
        description = "Automerge security updates immediately"
        matchDatasources = [
          "npm",
          "docker",
          "pypi"
        ]
        matchKeywords = [
          "security",
          "vulnerability",
          "CVE"
        ]
        automerge         = true
        minimumReleaseAge = "0 days"
      }
    ]
  })
}

resource "local_file" "renovate_extended_config" {
  filename = "${path.module}/../.renovaterc.json"
  content = jsonencode({
    extends = [
      "config:base",
      "schedule:weekly",
      ":dependencyDashboard"
    ]
    semanticCommits   = "enabled"
    autoMerge         = false
    autoMergeType     = "pr"
    autoMergeStrategy = "squash"
    updateTypes = [
      "patch",
      "minor",
      "digest",
      "bump",
      "pin",
      "rollback"
    ]
    semanticCommitType  = "chore"
    semanticCommitScope = "dependencies"
    grouping = {
      group1 = {
        description      = "Security updates"
        matchDatasources = ["docker", "npm", "pypi"]
        matchKeywords    = ["security", "vulnerability"]
        groupName        = "Security Updates"
        schedule         = ["at 3am on Monday"]
      }
      group2 = {
        description      = "Docker updates"
        matchDatasources = ["docker"]
        groupName        = "Docker Updates"
        automerge        = false
      }
      group3 = {
        description      = "Non-major updates"
        matchUpdateTypes = ["patch", "minor"]
        groupName        = "Dependencies"
        automerge        = true
      }
    }
  })
}

resource "local_file" "setup_renovate" {
  filename = "${path.module}/../scripts/setup-renovate.sh"
  content = templatefile("${path.module}/../templates/setup-renovate.sh.tpl", {
    renovate_version = var.renovate_version
  })
}

resource "local_file" "dependency_check_config" {
  filename = "${path.module}/../scripts/scan-dependencies.sh"
  content = templatefile("${path.module}/../templates/scan-dependencies.sh.tpl", {
    dependency_check_version = var.dependency_check_version
  })
}

resource "local_file" "cicd_renovate_pipeline" {
  filename = "${path.module}/../.github/workflows/renovate.yml"
  content = templatefile("${path.module}/../templates/renovate.yml.tpl", {
    renovate_version = var.renovate_version
  })
}

output "renovate_config" {
  value = {
    dependency_management = {
      tool     = "Renovate"
      version  = var.renovate_version
      schedule = "Weekly (Sunday 3 AM UTC)"
    }
    update_policy = {
      security_patches = {
        frequency  = "Immediate"
        auto_merge = true
        priority   = "P0"
      }
      bug_fixes = {
        frequency  = "Weekly"
        auto_merge = true
        priority   = "P2"
      }
      minor_updates = {
        frequency       = "Bi-weekly"
        auto_merge      = false
        priority        = "P3"
        requires_review = true
      }
      major_updates = {
        frequency                = "Monthly"
        auto_merge               = false
        priority                 = "P4"
        requires_detailed_review = true
      }
    }
    scanned_dependencies = [
      "Docker base images",
      "npm/Node.js packages",
      "Python packages",
      "Ubuntu LTS system packages",
      "Terraform providers",
      "Ansible roles"
    ]
    vulnerability_detection = {
      tool                = "Dependency-Check"
      version             = var.dependency_check_version
      alert_on_cve        = true
      block_deployment_if = "CRITICAL"
    }
    slo_targets = {
      daily_scan           = "Automated"
      pr_creation          = "< 1 minute"
      auto_merge_security  = "< 10 minutes if tests pass"
      manual_review_window = "48 hours for major"
      false_positive_rate  = "< 2%"
    }
  }
}
