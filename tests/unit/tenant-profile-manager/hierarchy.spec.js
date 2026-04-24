#!/usr/bin/env node
// @file        tests/unit/tenant-profile-manager/hierarchy.spec.ts
// @module      session/tenant-profiles
// @description Tenant-aware profile hierarchy and immutable policy tests
//
import { describe, it, beforeEach, afterEach, expect } from "vitest";
import { TenantProfileManager, createTenantProfileManager } from "../../../src/services/tenant-profile-manager";
import { computeProfileTemplateBundleChecksum, createProfileTemplateBundleManifest, getTemplateBundleFilePath, loadProfileTemplateBundle, validateProfileTemplateBundle, } from "../../../src/services/tenant-profile-manager/template-bundles";
import { ProfileLevel, LockedPolicyKey } from "../../../src/services/tenant-profile-manager/types";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
describe("TenantProfileManager - Hierarchy and Immutable Policy Tests", () => {
    let manager;
    let tempDir;
    beforeEach(async () => {
        // Create temporary directory for test profiles
        tempDir = path.join(os.tmpdir(), `profile-test-${Date.now()}`);
        await fs.promises.mkdir(tempDir, { recursive: true });
        manager = createTenantProfileManager(tempDir);
    });
    afterEach(async () => {
        // Clean up temporary directory
        if (fs.existsSync(tempDir)) {
            await fs.promises.rm(tempDir, { recursive: true, force: true });
        }
    });
    describe("1. Profile Hierarchy Merging", () => {
        it("should merge settings from all hierarchy levels", async () => {
            // Setup hierarchy
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            // Global policy
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                "editor.fontSize": 14,
                "editor.lineNumbers": "on",
            }));
            // Role policy (developer role)
            await fs.promises.writeFile(path.join(tempDir, "role-developer.json"), JSON.stringify({
                "editor.fontSize": 16, // Override global
                "[python]": { "editor.defaultFormatter": "ms-python.python" },
            }));
            // Team policy
            const teamPolicyPath = path.join(tempDir, "kushin77", "team-policy.json");
            await fs.promises.writeFile(teamPolicyPath, JSON.stringify({
                "editor.lineNumbers": "relative", // Override global
                "git.ignoreLimitWarning": true,
            }));
            // User preferences
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify({
                "editor.fontSize": 18, // Override all levels
                "editor.theme": "Dark+ (default dark)",
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: ["developer"],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            // Verify merged settings
            expect(result.settings.get("editor.fontSize")?.value).toBe(18); // User preference wins
            expect(result.settings.get("editor.lineNumbers")?.value).toBe("relative"); // Team policy
            expect(result.settings.get("editor.theme")?.value).toBe("Dark+ (default dark)"); // User only
            expect(result.settings.get("[python]")?.value).toBeDefined(); // From role policy
            expect(result.settings.get("git.ignoreLimitWarning")?.value).toBe(true); // From team policy
        });
        it("should preserve source information for each setting", async () => {
            // Setup minimal hierarchy
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                "editor.fontSize": 14,
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            const setting = result.settings.get("editor.fontSize");
            expect(setting?.source.level).toBe(ProfileLevel.GLOBAL_POLICY);
            expect(setting?.source.origin).toContain("global");
            expect(setting?.source.appliedAt).toBeGreaterThan(0);
        });
        it("should respect include/exclude user preferences flag", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                "editor.fontSize": 14,
            }));
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify({
                "editor.theme": "Light",
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            // Without user preferences
            const resultWithout = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            expect(resultWithout.settings.has("editor.theme")).toBe(false);
            // With user preferences
            const resultWith = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            expect(resultWith.settings.has("editor.theme")).toBe(true);
        });
    });
    describe("2. Immutable Key Enforcement", () => {
        it("should block user override of immutable keys", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            // Global policy with immutable extension list
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                [LockedPolicyKey.EXTENSIONS_ALLOWLIST]: ["ms-python.python"],
            }));
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            // User tries to override
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify({
                [LockedPolicyKey.EXTENSIONS_ALLOWLIST]: ["random-extension"], // Will be ignored
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: true,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            // Global policy value should be kept
            expect(result.settings.get(LockedPolicyKey.EXTENSIONS_ALLOWLIST)?.value).toEqual(["ms-python.python"]);
        });
        it("should enforce immutability on all locked policy keys", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            const lockedKeys = [
                LockedPolicyKey.EXTENSIONS_DENYLIST,
                LockedPolicyKey.GIT_AUTOCRLF,
                LockedPolicyKey.TERMINAL_ENV,
                LockedPolicyKey.KEYBINDINGS,
                LockedPolicyKey.MARKETPLACE_ENABLED,
                LockedPolicyKey.HTTP_PROXY,
                LockedPolicyKey.EXTENSIONS_RECOMMENDATIONS,
                LockedPolicyKey.EXTENSIONS_IGNORE_RECOMMENDATIONS,
            ];
            // Global policy sets all locked keys
            const globalPolicy = {};
            for (const key of lockedKeys) {
                globalPolicy[key] = `policy-${key}`;
            }
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify(globalPolicy));
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            // User tries to override all
            const userPrefs = {};
            for (const key of lockedKeys) {
                userPrefs[key] = `user-${key}`;
            }
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify(userPrefs));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: true,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            // All locked keys should have policy value
            for (const key of lockedKeys) {
                expect(result.settings.get(key)?.value).toBe(`policy-${key}`);
            }
        });
        it("should mark immutable settings correctly", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                [LockedPolicyKey.EXTENSIONS_ALLOWLIST]: ["ms-python.python"],
                "editor.fontSize": 14,
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            // Locked key should be marked immutable
            expect(result.settings.get(LockedPolicyKey.EXTENSIONS_ALLOWLIST)?.immutable).toBe(true);
            // Regular key should not be immutable
            expect(result.settings.get("editor.fontSize")?.immutable).toBe(false);
        });
        it("should prevent user from re-enabling extension recommendations", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            // Enterprise policy disables recommendations
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                [LockedPolicyKey.EXTENSIONS_RECOMMENDATIONS]: false,
                [LockedPolicyKey.EXTENSIONS_IGNORE_RECOMMENDATIONS]: true,
            }));
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            // User attempts to re-enable recommendations
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify({
                [LockedPolicyKey.EXTENSIONS_RECOMMENDATIONS]: true,
                [LockedPolicyKey.EXTENSIONS_IGNORE_RECOMMENDATIONS]: false,
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: true,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-extension-rec-override",
            });
            // Enterprise values must win — recommendations stay off
            expect(result.settings.get(LockedPolicyKey.EXTENSIONS_RECOMMENDATIONS)?.value).toBe(false);
            expect(result.settings.get(LockedPolicyKey.EXTENSIONS_IGNORE_RECOMMENDATIONS)?.value).toBe(true);
            expect(result.settings.get(LockedPolicyKey.EXTENSIONS_RECOMMENDATIONS)?.immutable).toBe(true);
            expect(result.settings.get(LockedPolicyKey.EXTENSIONS_IGNORE_RECOMMENDATIONS)?.immutable).toBe(true);
        });
    });
    describe("3. Namespace Isolation", () => {
        it("should isolate profiles by organization", async () => {
            // Create profiles for two different orgs
            await fs.promises.mkdir(path.join(tempDir, "org1"), { recursive: true });
            await fs.promises.mkdir(path.join(tempDir, "org2"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "org1", "team-policy.json"), JSON.stringify({
                "editor.theme": "org1-theme",
            }));
            await fs.promises.writeFile(path.join(tempDir, "org2", "team-policy.json"), JSON.stringify({
                "editor.theme": "org2-theme",
            }));
            const ns1 = manager.getNamespace("org1", "user@example.com");
            const ns2 = manager.getNamespace("org2", "user@example.com");
            const result1 = await manager.mergeProfiles({
                namespace: ns1,
                roles: [],
                org: "org1",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr-1",
            });
            const result2 = await manager.mergeProfiles({
                namespace: ns2,
                roles: [],
                org: "org2",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr-2",
            });
            expect(result1.settings.get("editor.theme")?.value).toBe("org1-theme");
            expect(result2.settings.get("editor.theme")?.value).toBe("org2-theme");
        });
        it("should isolate profiles by user within org", async () => {
            const orgPath = path.join(tempDir, "kushin77");
            await fs.promises.mkdir(orgPath, { recursive: true });
            const user1Path = path.join(orgPath, "user1_example_com");
            const user2Path = path.join(orgPath, "user2_example_com");
            await fs.promises.mkdir(user1Path, { recursive: true });
            await fs.promises.mkdir(user2Path, { recursive: true });
            await fs.promises.writeFile(path.join(user1Path, "preferences.json"), JSON.stringify({
                "editor.fontSize": 16,
            }));
            await fs.promises.writeFile(path.join(user2Path, "preferences.json"), JSON.stringify({
                "editor.fontSize": 14,
            }));
            const ns1 = manager.getNamespace("kushin77", "user1@example.com");
            const ns2 = manager.getNamespace("kushin77", "user2@example.com");
            const result1 = await manager.mergeProfiles({
                namespace: ns1,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr-1",
            });
            const result2 = await manager.mergeProfiles({
                namespace: ns2,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr-2",
            });
            expect(result1.settings.get("editor.fontSize")?.value).toBe(16);
            expect(result2.settings.get("editor.fontSize")?.value).toBe(14);
        });
        it("should prevent directory traversal in namespace paths", async () => {
            // Namespace should sanitize dangerous characters
            const ns = manager.getNamespace("kushin77", "../evil/../../etc/passwd");
            const path1 = ns.asPath();
            // Should not contain ../ or path separators
            expect(path1).not.toContain("..");
            expect(path1).not.toContain("/../");
            expect(path1).not.toContain("/etc/");
        });
    });
    describe("4. Drift Detection", () => {
        it("should detect unauthorized keys in user preferences", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                "editor.fontSize": 14,
            }));
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            // User adds unauthorized key
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify({
                "editor.fontSize": 14,
                "unauthorized.key": "should not be here",
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: false,
                detectDrift: true,
                auditLog: false,
                correlationId: "test-corr",
            });
            expect(result.driftDetected).toBe(true);
            expect(result.driftDetails?.length).toBeGreaterThan(0);
            expect(result.driftDetails?.some((d) => d.includes("unauthorized.key"))).toBe(true);
        });
        it("should detect modified values in user preferences", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                "editor.fontSize": 14,
            }));
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            // User modifies a merged value
            await fs.promises.writeFile(path.join(userPath, "preferences.json"), JSON.stringify({
                "editor.fontSize": 999, // Modified from global policy
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: true,
                enforceImmutability: false,
                detectDrift: true,
                auditLog: false,
                correlationId: "test-corr",
            });
            expect(result.driftDetected).toBe(true);
        });
    });
    describe("5. Role-Based Policies", () => {
        it("should merge policies from multiple roles", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            // Developer role
            await fs.promises.writeFile(path.join(tempDir, "role-developer.json"), JSON.stringify({
                "editor.defaultFormatter": "ms-python.python",
            }));
            // Admin role
            await fs.promises.writeFile(path.join(tempDir, "role-admin.json"), JSON.stringify({
                "extensions.allowlist": ["*"], // Admins can install any extension
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.mergeProfiles({
                namespace,
                roles: ["developer", "admin"],
                org: "kushin77",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            expect(result.settings.get("editor.defaultFormatter")?.value).toBeDefined();
            expect(result.settings.get("extensions.allowlist")?.value).toEqual(["*"]);
        });
    });
    describe("6. Caching", () => {
        it("should cache merged profiles", async () => {
            await fs.promises.mkdir(path.join(tempDir, "kushin77"), { recursive: true });
            await fs.promises.writeFile(path.join(tempDir, "global-policy.json"), JSON.stringify({
                "editor.fontSize": 14,
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            // First call
            const result1 = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            // Second call should be cached (same object reference if within TTL)
            const result2 = await manager.mergeProfiles({
                namespace,
                roles: [],
                org: "kushin77",
                includeUserPreferences: false,
                enforceImmutability: false,
                detectDrift: false,
                auditLog: false,
                correlationId: "test-corr",
            });
            // Both should have same computed time (within cache TTL)
            expect(result1.computedAt).toBe(result2.computedAt);
        });
    });
    describe("7. Recommendation/Marketplace Policy", () => {
        it("should load recommendation policy from workspace settings", async () => {
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            await fs.promises.writeFile(path.join(userPath, "recommendations.json"), JSON.stringify({
                recommendedExtensions: ["ms-python.python", "ms-vscode.cpptools"],
                forbiddenExtensions: ["evil-extension"],
                recommendedTheme: "Dark+ (default dark)",
                recommendedSettings: {
                    "python.linting.enabled": true,
                },
                policyVersion: "1.0",
                appliedAt: Date.now(),
            }));
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const policy = await manager.getRecommendationPolicy(namespace);
            expect(policy.recommendedExtensions).toContain("ms-python.python");
            expect(policy.forbiddenExtensions).toContain("evil-extension");
            expect(policy.recommendedTheme).toBe("Dark+ (default dark)");
        });
    });
    describe("8. Profile Application", () => {
        it("should apply settings at specific hierarchy levels", async () => {
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.applySetting(namespace, ProfileLevel.USER_PREFERENCES, "editor.fontSize", 16, "test-corr");
            expect(result.success).toBe(true);
            // Verify it was written
            const prefs = JSON.parse(await fs.promises.readFile(path.join(userPath, "preferences.json"), "utf-8"));
            expect(prefs["editor.fontSize"].value).toBe(16);
        });
        it("should reject immutable key application at user level", async () => {
            const userPath = path.join(tempDir, "kushin77", "test_example_com");
            await fs.promises.mkdir(userPath, { recursive: true });
            const namespace = manager.getNamespace("kushin77", "test@example.com");
            const result = await manager.applySetting(namespace, ProfileLevel.USER_PREFERENCES, LockedPolicyKey.EXTENSIONS_ALLOWLIST, ["random"], "test-corr");
            expect(result.success).toBe(false);
            expect(result.error).toContain("immutable");
        });
    });
    describe("9. Template Bundle Seeding", () => {
        it("should seed and sync a versioned baseline bundle", async () => {
            const bundleDir = path.join(os.tmpdir(), `template-bundle-${Date.now()}`);
            const profileDir = path.join(os.tmpdir(), `template-profile-${Date.now()}`);
            await fs.promises.mkdir(bundleDir, { recursive: true });
            await fs.promises.mkdir(profileDir, { recursive: true });
            try {
                const bundle = {
                    bundleId: "hardened-baseline-v1",
                    version: "1.0.0",
                    description: "Hardened baseline profile bundle for user projects",
                    owner: "platform",
                    createdAt: 1744934400000,
                    updatedAt: 1744934400000,
                    entries: [
                        {
                            level: ProfileLevel.GLOBAL_POLICY,
                            key: "extensions.ignoreRecommendations",
                            value: true,
                            immutable: true,
                        },
                        {
                            level: ProfileLevel.TEAM_POLICY,
                            key: "governance.ciChecks",
                            value: ["secrets-scan", "lint", "test", "sast-baseline"],
                        },
                        {
                            level: ProfileLevel.WORKSPACE_SETTINGS,
                            key: "workspace.templateBundleId",
                            value: "hardened-baseline-v1",
                        },
                    ],
                    starterPack: {
                        docs: ["docs/STANDARDS.md"],
                        ciChecks: ["scripts/ci/check-docs-metadata.sh"],
                        ssotLinks: [".env.schema.json"],
                    },
                    exceptionPolicy: {
                        policyReference: "docs/ops/PROFILE-TEMPLATE-BUNDLE.md",
                        issueTrackingRequired: true,
                        approvalRequired: true,
                        exceptionIssuePrefix: "template-exception",
                    },
                };
                const bundlePath = getTemplateBundleFilePath(bundleDir, bundle.bundleId);
                await fs.promises.writeFile(bundlePath, JSON.stringify(bundle, null, 2), "utf-8");
                const loadedBundle = await loadProfileTemplateBundle(bundlePath);
                expect(computeProfileTemplateBundleChecksum(loadedBundle)).toMatch(/^sha256:[a-f0-9]{64}$/i);
                const manifest = createProfileTemplateBundleManifest(loadedBundle, "corr-template");
                expect(manifest.entryCount).toBe(3);
                expect(manifest.starterPack.docs).toContain("docs/STANDARDS.md");
                const manager = new TenantProfileManager(profileDir, bundleDir);
                const namespace = manager.getNamespace("kushin77", "alice@example.com", "project-1");
                const seedResult = await manager.seedProfileFromTemplateBundle(namespace, "hardened-baseline-v1", "corr-seed");
                expect(seedResult.success).toBe(true);
                expect(seedResult.migratedSettings).toBe(3);
                const syncResult = await manager.syncProfileFromTemplateBundle(namespace, "hardened-baseline-v1", "corr-sync");
                expect(syncResult.success).toBe(true);
                expect(syncResult.skippedSettings).toBeGreaterThanOrEqual(1);
                const merged = await manager.mergeProfiles({
                    namespace,
                    roles: ["developer"],
                    org: "kushin77",
                    includeUserPreferences: false,
                    enforceImmutability: true,
                    detectDrift: false,
                    auditLog: false,
                    correlationId: "corr-merge",
                });
                expect(merged.settings.get("extensions.ignoreRecommendations")?.value).toBe(true);
                expect(merged.settings.get("governance.ciChecks")?.value).toEqual(["secrets-scan", "lint", "test", "sast-baseline"]);
                expect(merged.settings.get("workspace.templateBundleId")?.value).toBe("hardened-baseline-v1");
                const manifestPath = path.join(namespace.asPath(), "template-bundle-manifest.json");
                const starterPackPath = path.join(namespace.asPath(), "starter-pack.json");
                const exceptionPolicyPath = path.join(namespace.asPath(), "exception-policy.json");
                expect(fs.existsSync(manifestPath)).toBe(true);
                expect(fs.existsSync(starterPackPath)).toBe(true);
                expect(fs.existsSync(exceptionPolicyPath)).toBe(true);
                const manifestContent = JSON.parse(await fs.promises.readFile(manifestPath, "utf-8"));
                expect(manifestContent.bundleId).toBe("hardened-baseline-v1");
            }
            finally {
                await fs.promises.rm(bundleDir, { recursive: true, force: true });
                await fs.promises.rm(profileDir, { recursive: true, force: true });
            }
        });
        it("should reject malformed bundle metadata", () => {
            expect(() => validateProfileTemplateBundle({
                bundleId: "",
                version: "1.0.0",
                description: "broken",
                owner: "platform",
                createdAt: 0,
                updatedAt: 0,
                entries: [],
                starterPack: { docs: [], ciChecks: [], ssotLinks: [] },
                exceptionPolicy: {
                    policyReference: "docs/ops/PROFILE-TEMPLATE-BUNDLE.md",
                    issueTrackingRequired: true,
                    approvalRequired: true,
                    exceptionIssuePrefix: "template-exception",
                },
            })).toThrow("Template bundle id is required");
        });
    });
});
//# sourceMappingURL=hierarchy.spec.js.map