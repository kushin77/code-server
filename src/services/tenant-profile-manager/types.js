// @file        src/services/tenant-profile-manager/types.ts
// @module      session/tenant-profiles
// @description Tenant-aware profile hierarchy and immutable policy overlay types
//
/**
 * Profile hierarchy levels with precedence ordering.
 * Lower numeric value = higher precedence (overrides lower levels).
 */
export var ProfileLevel;
(function (ProfileLevel) {
    // Immutable defaults - lowest precedence
    ProfileLevel[ProfileLevel["GLOBAL_POLICY"] = 5] = "GLOBAL_POLICY";
    // Role-based settings
    ProfileLevel[ProfileLevel["ROLE_POLICY"] = 4] = "ROLE_POLICY";
    // Team/organization settings
    ProfileLevel[ProfileLevel["TEAM_POLICY"] = 3] = "TEAM_POLICY";
    // Workspace-specific settings
    ProfileLevel[ProfileLevel["WORKSPACE_SETTINGS"] = 2] = "WORKSPACE_SETTINGS";
    // User preferences - highest precedence (where allowed)
    ProfileLevel[ProfileLevel["USER_PREFERENCES"] = 1] = "USER_PREFERENCES";
})(ProfileLevel || (ProfileLevel = {}));
/**
 * Recommendation/marketplace policy keys that are locked.
 */
export var LockedPolicyKey;
(function (LockedPolicyKey) {
    // Extensions whitelist cannot be modified by user
    LockedPolicyKey["EXTENSIONS_ALLOWLIST"] = "extensions.allowlist";
    LockedPolicyKey["EXTENSIONS_DENYLIST"] = "extensions.denylist";
    // Git/SSH cannot be overridden
    LockedPolicyKey["GIT_AUTOCRLF"] = "git.autocrlf";
    LockedPolicyKey["GIT_AUTOSTAGE"] = "git.autostage";
    // Terminal/shell settings locked
    LockedPolicyKey["TERMINAL_ENV"] = "terminal.environment";
    LockedPolicyKey["TERMINAL_SHELL"] = "terminal.shell";
    LockedPolicyKey["TERMINAL_ARGS"] = "terminal.args";
    // Keybindings locked for security
    LockedPolicyKey["KEYBINDINGS"] = "keybindings";
    // Marketplace/extension settings
    LockedPolicyKey["MARKETPLACE_ENABLED"] = "marketplace.enabled";
    LockedPolicyKey["MARKETPLACE_ALLOWLIST"] = "marketplace.allowlist";
    // Extension recommendations — must not be re-enabled by user settings
    LockedPolicyKey["EXTENSIONS_RECOMMENDATIONS"] = "extensions.recommendations";
    LockedPolicyKey["EXTENSIONS_IGNORE_RECOMMENDATIONS"] = "extensions.ignoreRecommendations";
    // Proxy and network settings
    LockedPolicyKey["HTTP_PROXY"] = "http.proxy";
    LockedPolicyKey["HTTPS_PROXY"] = "https.proxy";
    // File watching and performance
    LockedPolicyKey["FILES_WATCHMAN_EXCLUDE"] = "files.watchedPathPattern";
})(LockedPolicyKey || (LockedPolicyKey = {}));
//# sourceMappingURL=types.js.map