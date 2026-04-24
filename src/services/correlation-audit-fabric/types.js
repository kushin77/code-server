// @file        src/services/correlation-audit-fabric/types.ts
// @module      audit/correlation
// @description End-to-end correlation-id audit fabric for decision traceability
//
/**
 * Audit decision type (decision point in the system)
 */
export var AuditDecisionType;
(function (AuditDecisionType) {
    AuditDecisionType["PORTAL_ASSERTION_ISSUED"] = "portal_assertion_issued";
    AuditDecisionType["GATEWAY_AUTHENTICATION"] = "gateway_authentication";
    AuditDecisionType["BOOTSTRAP_ENFORCEMENT"] = "bootstrap_enforcement";
    AuditDecisionType["POLICY_VERIFICATION"] = "policy_verification";
    AuditDecisionType["PROFILE_MERGE"] = "profile_merge";
    AuditDecisionType["ACL_CHECK"] = "acl_check";
    AuditDecisionType["REVOCATION_CHECK"] = "revocation_check";
    AuditDecisionType["PRIVILEGED_OPERATION"] = "privileged_operation";
    AuditDecisionType["WORKSPACE_LIFECYCLE"] = "workspace_lifecycle";
    AuditDecisionType["SESSION_TERMINATION"] = "session_termination";
})(AuditDecisionType || (AuditDecisionType = {}));
/**
 * Decision result
 */
export var DecisionResult;
(function (DecisionResult) {
    DecisionResult["ALLOWED"] = "allowed";
    DecisionResult["DENIED"] = "denied";
    DecisionResult["ERROR"] = "error";
    DecisionResult["DEFERRED"] = "deferred";
})(DecisionResult || (DecisionResult = {}));
//# sourceMappingURL=types.js.map