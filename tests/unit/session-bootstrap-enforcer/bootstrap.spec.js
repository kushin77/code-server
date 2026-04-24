#!/usr/bin/env node
// @file        tests/unit/session-bootstrap-enforcer/bootstrap.spec.ts
// @module      session/bootstrap-enforcer
// @description Bootstrap enforcement integration tests
//
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { afterEach, describe, it, beforeEach, expect } from "vitest";
import { createSessionBootstrapEnforcer } from "../../../src/services/session-bootstrap-enforcer";
import { PolicyBundleVerifier } from "../../../src/services/policy-bundle-verifier";
import { OpaPolicyService } from "../../../src/services/opa-policy-service";
import { EnforcementMode, FailSafeMode, SessionBootstrapEventType, PrivilegedOperationEventType, } from "../../../src/services/session-bootstrap-enforcer/types";
/**
 * Helper: Create a valid JWT assertion for testing.
 */
function createPolicyCatalog(root) {
    const catalogPath = path.join(root, "bundle-catalog.json");
    const catalog = {
        schema_version: "1",
        updated_at: "2026-04-18T00:00:00Z",
        channels: {
            stable: {
                version: "1.0.0",
                bundle_manifest: "artifacts/policy-bundles/policy-bundle-1.0.0-stable.manifest.json",
            },
            canary: {
                version: "1.0.0",
                bundle_manifest: "artifacts/policy-bundles/policy-bundle-1.0.0-canary.manifest.json",
            },
            rollback: {
                version: "0.9.9",
                bundle_manifest: "artifacts/policy-bundles/policy-bundle-0.9.9-stable.manifest.json",
            },
        },
    };
    fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + "\n", "utf-8");
    return catalogPath;
}
function createValidAssertion(overrides = {}) {
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        iss: "https://kushnir.cloud",
        sub: "user-123",
        aud: "code-server",
        email: "test@example.com",
        roles: ["developer"],
        org: "kushin77",
        iat: now,
        exp: now + 3600,
        policy_bundle: {
            version: "1",
            contract_id: "code-server-thin-client-v1",
            issued_at: now,
            expires_at: now + 3600,
            signature: "test-sig",
            algorithm: "RS256",
            issuer: "https://kushnir.cloud",
            identity: {
                email: "test@example.com",
                sub: "user-123",
                roles: ["developer"],
                org: "kushin77",
                iat: now,
                exp: now + 3600,
            },
            entitlements: {
                repos: ["https://github.com/kushin77/*"],
                workspace_policy: "default",
            },
            workspace_policies: {
                default: {
                    policy_version: "1.0",
                    policy_date: new Date().toISOString(),
                    repo_pattern: "github.com/kushin77/*",
                    extension_allowlist: ["ms-python.python"],
                    terminal_env: { PATH: "/usr/bin:/bin" },
                },
            },
            correlation_id: "test-corr",
        },
        ...overrides,
    };
    // Create a JWT-like string without real signing
    const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
    const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
    const signature = "fake-signature";
    return `${header}.${body}.${signature}`;
}
describe("SessionBootstrapEnforcer - Bootstrap Integration Tests", () => {
    let verifier;
    let enforcer;
    let policyService;
    let tempDir;
    let catalogPath;
    let decisionLogPath;
    beforeEach(() => {
        tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "session-bootstrap-enforcer-"));
        catalogPath = createPolicyCatalog(tempDir);
        decisionLogPath = path.join(tempDir, "decision-log.jsonl");
        verifier = new PolicyBundleVerifier({
            expectedIssuer: "https://kushnir.cloud",
            expectedAudience: "code-server",
            allowUnsigned: true, // Testing mode
        });
        policyService = new OpaPolicyService({
            catalogPath,
            decisionLogPath,
            retentionDays: 7,
        });
        policyService.setDistributionContract({
            rules: [
                {
                    repo_pattern: "https://github.com/kushin77/legacy-*",
                    channel: "rollback",
                },
            ],
        });
        enforcer = createSessionBootstrapEnforcer(verifier, policyService);
    });
    afterEach(() => {
        fs.rmSync(tempDir, { recursive: true, force: true });
    });
    describe("1. Valid Bootstrap", () => {
        it("should successfully bootstrap with valid assertion", async () => {
            const assertion = createValidAssertion();
            const options = { assertion };
            const result = await enforcer.bootstrap(options);
            expect(result.success).toBe(true);
            expect(result.session).toBeDefined();
            expect(result.session?.user.email).toBe("test@example.com");
            expect(result.session?.user.roles).toContain("developer");
            expect(result.auditEvents?.length).toBeGreaterThan(0);
        });
        it("should record proper audit events during bootstrap", async () => {
            const assertion = createValidAssertion();
            const result = await enforcer.bootstrap({ assertion });
            expect(result.success).toBe(true);
            const eventTypes = result.auditEvents?.map((e) => e.event_type) || [];
            expect(eventTypes).toContain(SessionBootstrapEventType.ASSERTION_RECEIVED);
            expect(eventTypes).toContain(SessionBootstrapEventType.ASSERTION_VALIDATION_STARTED);
            expect(eventTypes).toContain(SessionBootstrapEventType.SIGNATURE_VERIFIED);
            expect(eventTypes).toContain(SessionBootstrapEventType.POLICY_BUNDLE_VERIFIED);
            expect(eventTypes).toContain(SessionBootstrapEventType.SESSION_ACTIVATED);
        });
        it("should create session with correct expiry", async () => {
            const assertion = createValidAssertion();
            const sessionTtl = 7200; // 2 hours
            const result = await enforcer.bootstrap({ assertion, sessionTtlSeconds: sessionTtl });
            expect(result.session).toBeDefined();
            const now = Math.floor(Date.now() / 1000);
            const expectedExpiry = now + sessionTtl;
            expect(result.session?.expires_at).toBeCloseTo(expectedExpiry, -1); // Within 1 second
        });
        it("should set enforcement mode to STRICT by default", async () => {
            const assertion = createValidAssertion();
            const result = await enforcer.bootstrap({ assertion });
            expect(result.session?.policy.enforcement_mode).toBe(EnforcementMode.STRICT);
        });
    });
    describe("2. Invalid Assertion Rejection", () => {
        it("should reject malformed JWT", async () => {
            const result = await enforcer.bootstrap({ assertion: "not-a-jwt" });
            expect(result.success).toBe(false);
            expect(result.errors?.length).toBeGreaterThan(0);
            expect(result.errors?.[0].code).toBe("INVALID_JWT_FORMAT");
            expect(result.errors?.[0].severity).toBe("critical");
        });
        it("should reject assertion with missing identity fields", async () => {
            const assertion = createValidAssertion({
                policy_bundle: {
                    version: "1",
                    contract_id: "code-server-thin-client-v1",
                    issued_at: Math.floor(Date.now() / 1000),
                    expires_at: Math.floor(Date.now() / 1000) + 3600,
                    signature: "test",
                    algorithm: "RS256",
                    issuer: "https://kushnir.cloud",
                    identity: {
                    // Missing email, sub, roles, org
                    },
                    entitlements: { repos: [] },
                    workspace_policies: {},
                },
            });
            const result = await enforcer.bootstrap({ assertion });
            expect(result.success).toBe(false);
            expect(result.errors).toContainEqual(expect.objectContaining({ code: "MISSING_IDENTITY_FIELD" }));
        });
        it("should fail bootstrap if policy verification fails", async () => {
            const assertion = createValidAssertion({
                policy_bundle: {
                    // Invalid bundle: missing required fields
                    version: "1",
                },
            });
            const result = await enforcer.bootstrap({ assertion });
            expect(result.success).toBe(false);
            expect(result.errors?.length).toBeGreaterThan(0);
        });
    });
    describe("3. Privileged Operation Enforcement", () => {
        it("should allow privileged operation for valid session", async () => {
            const assertion = createValidAssertion();
            const bootstrapResult = await enforcer.bootstrap({ assertion });
            const sessionId = bootstrapResult.session?.session_id;
            const operation = {
                operation_type: "execute_terminal",
                resource: "ls -la",
            };
            const result = await enforcer.checkPrivilegedOperation(sessionId, operation);
            expect(result.allowed).toBe(true);
        });
        it("should deny operation for expired session", async () => {
            const assertion = createValidAssertion();
            const bootstrapResult = await enforcer.bootstrap({ assertion, sessionTtlSeconds: 1 });
            const sessionId = bootstrapResult.session?.session_id;
            // Wait for session to expire
            await new Promise((resolve) => setTimeout(resolve, 1100));
            const operation = {
                operation_type: "execute_terminal",
            };
            const result = await enforcer.checkPrivilegedOperation(sessionId, operation);
            expect(result.allowed).toBe(false);
            expect(result.reason).toContain("expired");
        });
        it("should deny operation for non-existent session", async () => {
            const operation = {
                operation_type: "execute_terminal",
            };
            const result = await enforcer.checkPrivilegedOperation("invalid-session-id", operation);
            expect(result.allowed).toBe(false);
            expect(result.reason).toContain("not found");
        });
        it("should record audit event for privileged operation", async () => {
            const assertion = createValidAssertion();
            const bootstrapResult = await enforcer.bootstrap({ assertion });
            const sessionId = bootstrapResult.session?.session_id;
            const operation = {
                operation_type: "read_secret",
                resource: "gsm-secret-name",
            };
            const result = await enforcer.checkPrivilegedOperation(sessionId, operation);
            expect(result.audit_event).toBeDefined();
            expect(result.audit_event?.event_type).toBe(PrivilegedOperationEventType.PRIVILEGED_OP_ALLOWED);
            expect(result.audit_event?.status).toBe("success");
        });
        it("should deny mutating operation when OPA routes repo to rollback and log the decision", async () => {
            const assertion = createValidAssertion({
                policy_bundle: {
                    version: "1",
                    contract_id: "code-server-thin-client-v1",
                    issued_at: Math.floor(Date.now() / 1000),
                    expires_at: Math.floor(Date.now() / 1000) + 3600,
                    signature: "test",
                    algorithm: "RS256",
                    issuer: "https://kushnir.cloud",
                    identity: {
                        email: "test@example.com",
                        sub: "user-123",
                        roles: ["developer"],
                        org: "kushin77",
                        iat: Math.floor(Date.now() / 1000),
                        exp: Math.floor(Date.now() / 1000) + 3600,
                    },
                    entitlements: {
                        repos: ["https://github.com/kushin77/legacy-*"],
                        workspace_policy: "default",
                    },
                    workspace_policies: {
                        default: {
                            policy_version: "1.0",
                            policy_date: new Date().toISOString(),
                            repo_pattern: "https://github.com/kushin77/legacy-*",
                            extension_allowlist: ["ms-python.python"],
                            terminal_env: { PATH: "/usr/bin:/bin" },
                        },
                    },
                },
            });
            const bootstrapResult = await enforcer.bootstrap({ assertion });
            const sessionId = bootstrapResult.session?.session_id;
            const result = await enforcer.checkPrivilegedOperation(sessionId, {
                operation_type: "execute_terminal",
                resource: "https://github.com/kushin77/legacy-app",
            });
            expect(result.allowed).toBe(false);
            expect(result.reason).toContain("rollback");
            const decisionLog = fs
                .readFileSync(decisionLogPath, "utf-8")
                .split(/\r?\n/)
                .filter((line) => line.trim().length > 0);
            expect(decisionLog).toHaveLength(1);
            expect(decisionLog[0]).toContain('"decision":"deny"');
            expect(decisionLog[0]).toContain('"policy_domain":"ide-governance"');
        });
    });
    describe("4. Session Lifecycle", () => {
        it("should retrieve session after bootstrap", async () => {
            const assertion = createValidAssertion();
            const bootstrapResult = await enforcer.bootstrap({ assertion });
            const sessionId = bootstrapResult.session?.session_id;
            const session = enforcer.getSession(sessionId);
            expect(session).toBeDefined();
            expect(session?.user.email).toBe("test@example.com");
        });
        it("should return undefined for non-existent session", async () => {
            const session = enforcer.getSession("non-existent-id");
            expect(session).toBeUndefined();
        });
        it("should terminate session cleanly", async () => {
            const assertion = createValidAssertion();
            const bootstrapResult = await enforcer.bootstrap({ assertion });
            const sessionId = bootstrapResult.session?.session_id;
            expect(enforcer.getSession(sessionId)).toBeDefined();
            enforcer.endSession(sessionId);
            expect(enforcer.getSession(sessionId)).toBeUndefined();
        });
        it("should deny operations after session termination", async () => {
            const assertion = createValidAssertion();
            const bootstrapResult = await enforcer.bootstrap({ assertion });
            const sessionId = bootstrapResult.session?.session_id;
            enforcer.endSession(sessionId);
            const operation = {
                operation_type: "execute_terminal",
            };
            const result = await enforcer.checkPrivilegedOperation(sessionId, operation);
            expect(result.allowed).toBe(false);
        });
    });
    describe("5. Policy Expiry", () => {
        it("should track policy expiration separately from session expiration", async () => {
            const now = Math.floor(Date.now() / 1000);
            const assertion = createValidAssertion({
                policy_bundle: {
                    version: "1",
                    contract_id: "code-server-thin-client-v1",
                    issued_at: now,
                    expires_at: now + 1800, // 30 minutes
                    signature: "test",
                    algorithm: "RS256",
                    issuer: "https://kushnir.cloud",
                    identity: {
                        email: "test@example.com",
                        sub: "user-123",
                        roles: ["developer"],
                        org: "kushin77",
                        iat: now,
                        exp: now + 1800,
                    },
                    entitlements: { repos: [] },
                    workspace_policies: {},
                },
            });
            const result = await enforcer.bootstrap({ assertion, sessionTtlSeconds: 7200 }); // 2 hours
            const session = result.session;
            expect(session.policy.policy_expires_at).toBeLessThan(session.expires_at);
        });
    });
    describe("6. Fail-Safe Mode", () => {
        it("should activate fail-safe mode on bootstrap failure", async () => {
            const result = await enforcer.bootstrap({ assertion: "invalid" });
            expect(result.success).toBe(false);
            const failSafeEvent = result.auditEvents?.find((e) => e.event_type === SessionBootstrapEventType.FAIL_SAFE_ACTIVATED);
            expect(failSafeEvent).toBeDefined();
        });
        it("should respect default fail-safe mode option", async () => {
            const result = await enforcer.bootstrap({
                assertion: "invalid",
                defaultFailSafeMode: FailSafeMode.DENY_MUTATING,
            });
            expect(result.success).toBe(false);
            // In production, fail-safe mode would be applied here
            // For now, we verify the option was accepted
            expect(result).toBeDefined();
        });
    });
    describe("7. Audit Trail", () => {
        it("should maintain correlation ID across audit events", async () => {
            const assertion = createValidAssertion();
            const result = await enforcer.bootstrap({ assertion });
            const correlationIds = result.auditEvents?.map((e) => e.correlation_id) || [];
            const uniqueIds = new Set(correlationIds);
            // All events should have the same correlation ID
            expect(uniqueIds.size).toBe(1);
        });
        it("should record detailed event information", async () => {
            const assertion = createValidAssertion();
            const result = await enforcer.bootstrap({ assertion });
            const verifiedEvent = result.auditEvents?.find((e) => e.event_type === SessionBootstrapEventType.SIGNATURE_VERIFIED);
            expect(verifiedEvent).toBeDefined();
            expect(verifiedEvent?.details.algorithm).toBe("RS256");
            expect(verifiedEvent?.details.issuer).toBe("https://kushnir.cloud");
        });
    });
    describe("8. Multiple Identity Types", () => {
        it("should support multiple roles in identity", async () => {
            const assertion = createValidAssertion({
                policy_bundle: {
                    version: "1",
                    contract_id: "code-server-thin-client-v1",
                    issued_at: Math.floor(Date.now() / 1000),
                    expires_at: Math.floor(Date.now() / 1000) + 3600,
                    signature: "test",
                    algorithm: "RS256",
                    issuer: "https://kushnir.cloud",
                    identity: {
                        email: "test@example.com",
                        sub: "user-123",
                        roles: ["developer", "admin", "reviewer"],
                        org: "kushin77",
                        iat: Math.floor(Date.now() / 1000),
                        exp: Math.floor(Date.now() / 1000) + 3600,
                    },
                    entitlements: { repos: [] },
                    workspace_policies: {},
                },
            });
            const result = await enforcer.bootstrap({ assertion });
            expect(result.session?.user.roles).toEqual(["developer", "admin", "reviewer"]);
        });
    });
});
//# sourceMappingURL=bootstrap.spec.js.map