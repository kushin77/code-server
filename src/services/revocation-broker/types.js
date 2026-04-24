// @file        src/services/revocation-broker/types.ts
// @module      identity/revocation
// @description Type definitions for strict revocation path with propagation SLO enforcement
//
/**
 * Revocation status for user, session, or privilege
 */
export var RevocationStatus;
(function (RevocationStatus) {
    RevocationStatus["ACTIVE"] = "active";
    RevocationStatus["REVOKED"] = "revoked";
    RevocationStatus["REVOKE_PENDING"] = "revoke_pending";
    RevocationStatus["UNKNOWN"] = "unknown";
})(RevocationStatus || (RevocationStatus = {}));
/**
 * Scope of revocation (what is being revoked)
 */
export var RevocationScope;
(function (RevocationScope) {
    RevocationScope["USER"] = "user";
    RevocationScope["SESSION"] = "session";
    RevocationScope["PRIVILEGE"] = "privilege";
    RevocationScope["WORKSPACE"] = "workspace";
})(RevocationScope || (RevocationScope = {}));
/**
 * Reason for revocation
 */
export var RevocationReason;
(function (RevocationReason) {
    RevocationReason["ADMIN_EXPLICIT"] = "admin_explicit";
    RevocationReason["POLICY_VIOLATION"] = "policy_violation";
    RevocationReason["EMPLOYMENT_TERMINATION"] = "employment_termination";
    RevocationReason["SECURITY_INCIDENT"] = "security_incident";
    RevocationReason["MFA_FAILURE"] = "mfa_failure";
    RevocationReason["LICENSE_EXPIRY"] = "license_expiry";
    RevocationReason["MANUAL_DEPROVISIONING"] = "manual_deprovisioning";
    RevocationReason["SYSTEM_EMERGENCY"] = "system_emergency";
})(RevocationReason || (RevocationReason = {}));
/**
 * Enforcement mode for unknown revocation state
 */
export var UnknownRevocationBehavior;
(function (UnknownRevocationBehavior) {
    UnknownRevocationBehavior["DENY"] = "deny";
    UnknownRevocationBehavior["ALLOW"] = "allow";
    UnknownRevocationBehavior["LOCK_DOWN"] = "lock_down";
})(UnknownRevocationBehavior || (UnknownRevocationBehavior = {}));
//# sourceMappingURL=types.js.map