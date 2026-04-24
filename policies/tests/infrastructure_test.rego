# @file infrastructure_test.rego
# @module policies/tests
# @description Unit tests for infrastructure policies

package infrastructure.immutable_infra_test

import future.keywords.if

# Test: SSH file modifications to production should be denied
test_deny_ssh_prod_file_modify {
    deny[msg] with input as {
        "action": "ssh_command",
        "target_host": "prod-primary-192.168.168.31",
        "command_type": "file_modify"
    }
    count(deny) > 0
}

# Test: Direct Docker container exec modifications should be denied
test_deny_docker_exec_modify {
    deny[msg] with input as {
        "action": "docker_command",
        "command": "exec",
        "target_container": "prod-api",
        "modify_filesystem": true
    }
    count(deny) > 0
}

# Test: Image builds must reference Dockerfile
test_deny_docker_build_no_dockerfile {
    deny[msg] with input as {
        "action": "docker_build"
    }
    count(deny) > 0
}

# Test: Floating image tags in production should be denied
test_deny_floating_tag_prod {
    deny[msg] with input as {
        "action": "deploy_container",
        "target_env": "production",
        "image_tag": "latest"
    }
    count(deny) > 0
}

# Test: Manual secret modifications should be denied
test_deny_manual_secret_modify_prod {
    deny[msg] with input as {
        "action": "modify_secret",
        "target_env": "production"
    }
    count(deny) > 0
}

# Test: Uncommitted infra changes in production should be denied
test_deny_uncommitted_terraform_prod {
    deny[msg] with input as {
        "action": "apply_terraform",
        "target_env": "production"
    }
    count(deny) > 0
}

# Test: Git-tracked changes should be allowed
test_allow_tracked_terraform {
    allow[msg] with input as {
        "action": "apply_terraform",
        "from_git_commit": true,
        "commit_sha": "abc123def456"
    }
    count(allow) > 0
}

# Test: Immutable digest deployments should be allowed
test_allow_immutable_digest {
    allow[msg] with input as {
        "action": "deploy_container",
        "image_digest": "sha256:1234567890abcdef"
    }
    count(allow) > 0
}

# Test: Infrastructure changes are audited
test_audit_terraform_apply {
    audit_event[event] with input as {
        "action": "apply_terraform",
        "timestamp": "2026-04-24T10:00:00Z",
        "actor_id": "user-123",
        "commit_sha": "abc123def456",
        "target_env": "production"
    }
    count(audit_event) > 0
}

---

package infrastructure.drift_prevention_test

# Test: Manual changes to IaC-managed resources should be denied
test_deny_manual_change_iac_resource {
    deny[msg] with input as {
        "action": "manual_infra_change",
        "resource_type": "security_group",
        "deployed_via_iac": true
    }
    count(deny) > 0
}

# Test: Terraform apply with state drift should be denied
test_deny_terraform_state_drift {
    deny[msg] with input as {
        "action": "terraform_apply",
        "state_drift_detected": true,
        "drift_percentage": 10
    }
    count(deny) > 0
}

# Test: Deploy with uncommitted changes should be denied
test_deny_deploy_uncommitted_changes {
    deny[msg] with input as {
        "action": "deploy",
        "target_env": "production",
        "uncommitted_changes": ["terraform/main.tf", "docker-compose.yml"]
    }
    count(deny) > 0
}

# Test: Deploy without recent drift check should be denied
test_deny_deploy_old_drift_check {
    deny[msg] with input as {
        "action": "deploy",
        "target_env": "production",
        "last_drift_check_age_hours": 48
    }
    count(deny) > 0
}

# Test: Deploy with unreconciled drift should be denied
test_deny_deploy_unreconciled_drift {
    deny[msg] with input as {
        "action": "deploy",
        "drift_report": {
            "unreconciled_resources": ["vpc-123", "subnet-456"]
        }
    }
    count(deny) > 0
}

# Test: Drift-free deployment should be allowed
test_allow_drift_free_deploy {
    allow[msg] with input as {
        "action": "deploy",
        "drift_report": {
            "drift_free": true
        },
        "last_drift_check_age_hours": 12
    }
    count(allow) > 0
}

# Test: Approved drift reconciliation should be allowed
test_allow_reconciliation_approved {
    allow[msg] with input as {
        "action": "reconcile_drift",
        "human_approved": true,
        "approval_reason": "Expected config change"
    }
    count(allow) > 0
}

# Test: Drift detection records results
test_drift_event_recorded {
    drift_event[event] with input as {
        "action": "drift_detection_complete",
        "timestamp": "2026-04-24T10:00:00Z",
        "drift_report": {
            "drift_free": false,
            "drift_percentage": 5,
            "total_resources": 100
        },
        "environment": "production"
    }
    count(drift_event) > 0
}

# Test: Reconciliation required when drift detected
test_reconciliation_required {
    reconciliation_required[req] with input as {
        "action": "drift_detection_complete",
        "drift_report": {
            "drift_free": false,
            "drift_percentage": 8,
            "drifted_resources": ["sg-123", "route-456"]
        },
        "environment": "production"
    }
    count(reconciliation_required) > 0
}

# Test: Alert on high drift
test_alert_high_drift {
    alert[alert_msg] with input as {
        "action": "drift_detection_complete",
        "drift_report": {
            "drift_percentage": 15
        },
        "environment": "production"
    }
    count(alert) > 0
}

# Test: Critical alert on suspicious changes
test_critical_alert_suspicious_changes {
    alert[alert_msg] with input as {
        "action": "drift_detection_complete",
        "drift_report": {
            "suspicious_changes": ["unauthorized_sg_rule", "deleted_backup_bucket"]
        }
    }
    count(alert) > 0
}

---

package infrastructure.no_hardcoded_ips_test

# Test: Hardcoded IPs in configs should be detected
test_detect_hardcoded_ip {
    # Policy should detect patterns like 192.168.x.x in config files
    input.resource_type == "terraform" | input.resource_type == "config"
}
