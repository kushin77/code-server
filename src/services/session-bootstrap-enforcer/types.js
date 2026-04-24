#!/usr/bin/env node
// @file        src/services/session-bootstrap-enforcer/types.ts
// @module      session/bootstrap-enforcer
// @description Type definitions for session bootstrap enforcement
//
export { FailSafeMode } from "../policy-bundle-verifier";
/**
 * Policy enforcement mode determines what operations are allowed.
 */
export var EnforcementMode;
(function (EnforcementMode) {
    EnforcementMode["STRICT"] = "strict";
    EnforcementMode["DEGRADED"] = "degraded";
    EnforcementMode["LOCKED_DOWN"] = "locked_down";
})(EnforcementMode || (EnforcementMode = {}));
/**
 * Event types during session bootstrap.
 */
export var SessionBootstrapEventType;
(function (SessionBootstrapEventType) {
    SessionBootstrapEventType["ASSERTION_RECEIVED"] = "assertion_received";
    SessionBootstrapEventType["ASSERTION_VALIDATION_STARTED"] = "assertion_validation_started";
    SessionBootstrapEventType["SIGNATURE_VERIFIED"] = "signature_verified";
    SessionBootstrapEventType["POLICY_BUNDLE_VERIFIED"] = "policy_bundle_verified";
    SessionBootstrapEventType["SESSION_ACTIVATED"] = "session_activated";
    SessionBootstrapEventType["BOOTSTRAP_FAILED"] = "bootstrap_failed";
    SessionBootstrapEventType["FAIL_SAFE_ACTIVATED"] = "fail_safe_activated";
})(SessionBootstrapEventType || (SessionBootstrapEventType = {}));
/**
 * Event types for privileged operations.
 */
export var PrivilegedOperationEventType;
(function (PrivilegedOperationEventType) {
    PrivilegedOperationEventType["PRIVILEGED_OP_ATTEMPTED"] = "privileged_op_attempted";
    PrivilegedOperationEventType["PRIVILEGED_OP_ALLOWED"] = "privileged_op_allowed";
    PrivilegedOperationEventType["PRIVILEGED_OP_DENIED"] = "privileged_op_denied";
    PrivilegedOperationEventType["POLICY_DRIFT_DETECTED"] = "policy_drift_detected";
})(PrivilegedOperationEventType || (PrivilegedOperationEventType = {}));
//# sourceMappingURL=types.js.map