#!/usr/bin/env node
// @file        src/services/policy-bundle-verifier/schema.ts
// @module      policy/bundle-verifier
// @description Type definitions and schemas for policy bundle verification
//
/**
 * Fail-safe mode configuration.
 */
export var FailSafeMode;
(function (FailSafeMode) {
    FailSafeMode["DENY_ALL"] = "deny-all";
    FailSafeMode["DENY_MUTATING"] = "deny-mutating";
    FailSafeMode["READ_ONLY_CACHE"] = "read-only-cache";
})(FailSafeMode || (FailSafeMode = {}));
//# sourceMappingURL=schema.js.map