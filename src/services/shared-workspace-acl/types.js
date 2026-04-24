// @file        src/services/shared-workspace-acl/types.ts
// @module      workspace/acl
// @description Shared workspace ACL model for controlled folder sharing with role-based access
//
/**
 * Shared workspace access control model.
 * Provides explicit governance for shared folder access with owner/editor/viewer roles.
 */
/**
 * Access level grant for shared workspace.
 */
export var AccessLevel;
(function (AccessLevel) {
    // View-only access
    AccessLevel["VIEWER"] = "viewer";
    // Can read and write (create/edit/delete)
    AccessLevel["EDITOR"] = "editor";
    // Full control including ACL management and revocation
    AccessLevel["OWNER"] = "owner";
})(AccessLevel || (AccessLevel = {}));
/**
 * ACL event types.
 */
export var AclEventType;
(function (AclEventType) {
    AclEventType["ACCESS_GRANTED"] = "access_granted";
    AclEventType["ACCESS_REVOKED"] = "access_revoked";
    AclEventType["ACCESS_UPDATED"] = "access_updated";
    AclEventType["ACCESS_EXPIRED"] = "access_expired";
    AclEventType["LEASE_RENEWED"] = "lease_renewed";
    AclEventType["EMERGENCY_REVOKE"] = "emergency_revoke";
    AclEventType["ACL_MODIFIED"] = "acl_modified";
})(AclEventType || (AclEventType = {}));
//# sourceMappingURL=types.js.map