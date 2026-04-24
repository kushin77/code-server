# @file device_trust.rego
# @module policies/identity
# @description Enforce device compliance and trust score checks for sensitive operations
# @governance GOV-003 - Device Trust & Compliance

package identity.device_trust

import future.keywords.if
import future.keywords.contains

# Device trust score calculation criteria
trust_requirements := {
    "read_data": 0,
    "write_data": 30,
    "delete_data": 60,
    "access_secrets": 80,
    "deploy_prod": 90,
}

high_trust_operations := {"access_secrets", "deploy_prod"}

# Deny operations from untrusted/unknown devices
deny[msg] {
    input.action == "access_sensitive_resource"
    not input.device_id
    msg := "Access denied: device identification required for sensitive resources"
}

# Deny if device trust score below operation threshold
deny[msg] {
    input.action == "access_sensitive_resource"
    input.operation_type
    trust_requirements[input.operation_type]
    required_trust := trust_requirements[input.operation_type]
    input.device_trust_score < required_trust
    msg := sprintf("Device trust too low: %d (required %d for '%s')", 
        [input.device_trust_score, required_trust, input.operation_type])
}

# Deny if device is not on managed/approved device list (for high-trust ops)
deny[msg] {
    input.action == "access_sensitive_resource"
    high_trust_operations[input.operation_type]
    not input.device_managed
    msg := "Access denied: unmanaged device cannot access this resource (admin enrollment required)"
}

# Deny if device compliance check fails
deny[msg] {
    input.action == "access_sensitive_resource"
    input.device_compliance_check
    not input.device_compliance_check.passed
    msg := sprintf("Device compliance check failed: %s", 
        [input.device_compliance_check.failure_reason])
}

# Deny if device has security incident history
deny[msg] {
    input.action == "access_sensitive_resource"
    input.device_id
    input.security_incidents
    count(input.security_incidents) > 0
    msg := sprintf("Device has active security incidents (%d), access denied", 
        [count(input.security_incidents)])
}

# Allow access if device trust score sufficient
allow[msg] {
    input.action == "access_sensitive_resource"
    input.device_id
    input.operation_type
    trust_requirements[input.operation_type]
    required_trust := trust_requirements[input.operation_type]
    input.device_trust_score >= required_trust
    msg := sprintf("Device trust verified (%d/%d) for operation '%s'", 
        [input.device_trust_score, required_trust, input.operation_type])
}

# Update device trust score based on behavior
trust_score_adjustment[adjustment] {
    input.action == "successful_operation"
    adjustment := {
        "device_id": input.device_id,
        "increase": 5,
        "reason": "successful_secure_operation"
    }
}

# Decrease trust score on suspicious activity
trust_score_adjustment[adjustment] {
    input.action == "suspicious_activity_detected"
    adjustment := {
        "device_id": input.device_id,
        "decrease": 20,
        "reason": input.activity_type
    }
}
