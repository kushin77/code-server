# @file drift_prevention.rego
# @module policies/infrastructure
# @description Prevent infrastructure drift through reconciliation enforcement
# @governance GOV-003 - Infrastructure Drift Prevention

package infrastructure.drift_prevention

import future.keywords.if
import future.keywords.contains

# Deny manual infrastructure changes after IaC deployment
deny[msg] {
    input.action == "manual_infra_change"
    input.resource_type
    input.deployed_via_iac == true
    msg := sprintf("Drift detected: manual change to IaC-managed resource '%s'. Use terraform plan/apply instead.", 
        [input.resource_type])
}

# Deny Terraform apply if state is out of sync
deny[msg] {
    input.action == "terraform_apply"
    input.state_drift_detected == true
    input.drift_percentage > 5
    msg := sprintf("Terraform state drift exceeds 5%% (%d%%). Run drift detection and reconciliation first.", 
        [input.drift_percentage])
}

# Deny deployment if uncommitted local changes exist
deny[msg] {
    input.action == "deploy"
    input.target_env == "production"
    input.uncommitted_changes
    count(input.uncommitted_changes) > 0
    msg := sprintf("Cannot deploy with uncommitted changes (%d files). Commit all changes first.", 
        [count(input.uncommitted_changes)])
}

# Deny if drift detection hasn't been run recently
deny[msg] {
    input.action == "deploy"
    input.target_env == "production"
    input.last_drift_check_age_hours
    input.last_drift_check_age_hours > 24
    msg := "Drift detection must be run before production deploy (last run >24h ago)"
}

# Deny if drift check failed or shows unreconciled drift
deny[msg] {
    input.action == "deploy"
    input.drift_report
    input.drift_report.unreconciled_resources
    count(input.drift_report.unreconciled_resources) > 0
    msg := sprintf("Cannot deploy with unreconciled drift (%d resources misaligned with IaC). Reconcile first.", 
        [count(input.drift_report.unreconciled_resources)])
}

# Allow deployment if drift-free
allow[msg] {
    input.action == "deploy"
    input.drift_report
    input.drift_report.drift_free == true
    input.last_drift_check_age_hours <= 24
    msg := "Deployment approved: infrastructure is drift-free and current"
}

# Allow manual reconciliation after approval
allow[msg] {
    input.action == "reconcile_drift"
    input.human_approved == true
    input.approval_reason
    msg := sprintf("Drift reconciliation approved: %s", [input.approval_reason])
}

# Record drift detection results
drift_event[event] {
    input.action == "drift_detection_complete"
    event := {
        "timestamp": input.timestamp,
        "drift_free": input.drift_report.drift_free,
        "drift_percentage": input.drift_report.drift_percentage,
        "resources_checked": input.drift_report.total_resources,
        "environment": input.environment
    }
}

# Require reconciliation if drift detected
reconciliation_required[req] {
    input.action == "drift_detection_complete"
    input.drift_report.drift_free == false
    req := {
        "environment": input.environment,
        "drift_percentage": input.drift_report.drift_percentage,
        "action_required": "reconcile",
        "resources": input.drift_report.drifted_resources
    }
}

# Alert on significant drift
alert[alert_msg] {
    input.action == "drift_detection_complete"
    input.drift_report.drift_percentage > 10
    alert_msg := sprintf("ALERT: High drift detected (%d%%) in %s environment - reconciliation recommended",
        [input.drift_report.drift_percentage, input.environment])
}

# Critical alert on suspicious drift
alert[alert_msg] {
    input.action == "drift_detection_complete"
    input.drift_report.suspicious_changes
    count(input.drift_report.suspicious_changes) > 0
    alert_msg := sprintf("CRITICAL: Suspicious manual changes detected (%d resources). Security review recommended.",
        [count(input.drift_report.suspicious_changes)])
}
