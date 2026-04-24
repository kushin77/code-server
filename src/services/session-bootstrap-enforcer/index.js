#!/usr/bin/env node
// @file        src/services/session-bootstrap-enforcer/index.ts
// @module      session/bootstrap-enforcer
// @description Session bootstrap enforcement with mandatory assertion validation
//
import * as crypto from "crypto";
import { SessionBootstrapEventType, PrivilegedOperationEventType, EnforcementMode, FailSafeMode, } from "./types";
/**
 * SessionBootstrapEnforcer manages session creation with mandatory assertion validation.
 * Ensures all code-server sessions are backed by a valid portal-issued assertion.
 */
export class SessionBootstrapEnforcer {
    constructor(verifier, policyService) {
        this.sessions = new Map();
        this.verifier = verifier;
        this.policyService = policyService;
    }
    /**
     * Bootstrap a new session with mandatory assertion validation.
     * This is the main entry point that code-server calls at startup.
     */
    async bootstrap(options) {
        const sessionId = this.generateSessionId();
        const auditEvents = [];
        const errors = [];
        try {
            // Step 1: Receive assertion
            this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.ASSERTION_RECEIVED, {
                assertion_length: options.assertion.length,
            });
            // Step 2: Decode and validate JWT format
            let decodedToken;
            try {
                decodedToken = this.decodeJwtWithoutVerification(options.assertion);
                if (!decodedToken) {
                    throw new Error("Invalid JWT format");
                }
            }
            catch (err) {
                errors.push({
                    code: "INVALID_JWT_FORMAT",
                    message: `Failed to decode assertion: ${err instanceof Error ? err.message : String(err)}`,
                    severity: "critical",
                });
                return this.createBootstrapFailure(sessionId, errors, auditEvents, options);
            }
            // Step 3: Parse policy bundle from assertion claims
            let bundle;
            try {
                const bundleData = decodedToken.payload.policy_bundle || decodedToken.payload;
                bundle = this.normalizePolicyBundle(bundleData);
            }
            catch (err) {
                errors.push({
                    code: "INVALID_BUNDLE_FORMAT",
                    message: `Failed to parse policy bundle: ${err instanceof Error ? err.message : String(err)}`,
                    severity: "critical",
                });
                return this.createBootstrapFailure(sessionId, errors, auditEvents, options);
            }
            // Step 4: Verify signature and policy validity
            this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.ASSERTION_VALIDATION_STARTED, {
                issuer: bundle.issuer,
            });
            const verificationResult = await this.verifier.verify(bundle);
            if (!verificationResult.valid) {
                errors.push(...verificationResult.errors.map((e) => ({
                    code: e.code,
                    message: e.message,
                    severity: this.mapVerificationErrorSeverity(e.code),
                    details: e.details,
                })));
                this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.BOOTSTRAP_FAILED, {
                    verification_errors: verificationResult.errors.length,
                });
                return this.createBootstrapFailure(sessionId, errors, auditEvents, options);
            }
            this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.SIGNATURE_VERIFIED, {
                algorithm: bundle.algorithm,
                issuer: bundle.issuer,
            });
            // Step 5: Validate identity assertion
            this.validateIdentityAssertion(bundle.identity, errors);
            if (errors.length > 0) {
                return this.createBootstrapFailure(sessionId, errors, auditEvents, options);
            }
            // Step 6: Apply policy bundle
            this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.POLICY_BUNDLE_VERIFIED, {
                policy_version: bundle.version,
                workspace_policies: Object.keys(bundle.workspace_policies),
            });
            // Step 7: Cache verified bundle
            this.verifier.cacheBundle(bundle, verificationResult, 300);
            // Step 8: Create and activate session
            const sessionContext = this.createSessionContext(sessionId, bundle, verificationResult.verified_at, options.sessionTtlSeconds || 3600, bundle.correlation_id || sessionId);
            // Step 9: Record session activation
            this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.SESSION_ACTIVATED, {
                user: sessionContext.user.email,
                org: sessionContext.user.org,
                enforcement_mode: sessionContext.policy.enforcement_mode,
            });
            // Store session
            this.sessions.set(sessionId, sessionContext);
            return {
                success: true,
                session: sessionContext,
                auditEvents,
            };
        }
        catch (err) {
            errors.push({
                code: "BOOTSTRAP_ERROR",
                message: `Unexpected error during bootstrap: ${err instanceof Error ? err.message : String(err)}`,
                severity: "critical",
            });
            return this.createBootstrapFailure(sessionId, errors, auditEvents, options);
        }
    }
    /**
     * Check if a session is still valid and authorized for a privileged operation.
     */
    async checkPrivilegedOperation(sessionId, operation) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            return {
                allowed: false,
                reason: "Session not found",
            };
        }
        const auditEvent = {
            timestamp: Math.floor(Date.now() / 1000),
            event_type: PrivilegedOperationEventType.PRIVILEGED_OP_ATTEMPTED,
            status: "failure",
            details: { operation_type: operation.operation_type, resource: operation.resource },
            correlation_id: session.correlation_id,
        };
        // Check if session has expired
        const now = Math.floor(Date.now() / 1000);
        if (now >= session.expires_at) {
            auditEvent.details.reason = "Session expired";
            this.sessions.delete(sessionId);
            return {
                allowed: false,
                reason: "Session expired",
                audit_event: auditEvent,
            };
        }
        // Check if policy has expired
        if (now > session.policy.policy_expires_at) {
            auditEvent.details.reason = "Policy expired";
            return {
                allowed: false,
                reason: "Policy expired",
                audit_event: auditEvent,
            };
        }
        // Check fail-safe status
        if (session.fail_safe_active && session.fail_safe_mode === FailSafeMode.DENY_ALL) {
            auditEvent.details.reason = "Fail-safe deny-all mode active";
            return {
                allowed: false,
                reason: "System in fail-safe mode",
                audit_event: auditEvent,
            };
        }
        // Check policy-based authorization for the operation
        const policyResult = await this.checkPolicyAuthorization(session, operation);
        if (!policyResult.allowed) {
            auditEvent.details.reason = policyResult.reason || "Policy does not allow operation";
            auditEvent.details.policy_repo = policyResult.repo;
            auditEvent.details.policy_action = policyResult.action;
            if (policyResult.decision) {
                auditEvent.details.policy_decision = policyResult.decision.decision;
                auditEvent.details.policy_channel = policyResult.decision.channel;
                auditEvent.details.policy_bundle_version = policyResult.decision.bundleVersion;
            }
            return {
                allowed: false,
                reason: policyResult.reason || "Operation not allowed by policy",
                audit_event: auditEvent,
            };
        }
        auditEvent.details.policy_repo = policyResult.repo;
        auditEvent.details.policy_action = policyResult.action;
        if (policyResult.decision) {
            auditEvent.details.policy_decision = policyResult.decision.decision;
            auditEvent.details.policy_channel = policyResult.decision.channel;
            auditEvent.details.policy_bundle_version = policyResult.decision.bundleVersion;
            auditEvent.details.policy_reason = policyResult.decision.reason;
        }
        // Detect policy drift
        const drift = this.detectPolicyDrift(session);
        if (drift.drifted && session.policy.enforcement_mode === EnforcementMode.STRICT) {
            auditEvent.event_type = PrivilegedOperationEventType.POLICY_DRIFT_DETECTED;
            auditEvent.details.drifted_fields = drift.drifted_fields;
            return {
                allowed: false,
                reason: "Policy drift detected",
                audit_event: auditEvent,
            };
        }
        // Operation allowed
        auditEvent.event_type = PrivilegedOperationEventType.PRIVILEGED_OP_ALLOWED;
        auditEvent.status = "success";
        return {
            allowed: true,
            audit_event: auditEvent,
        };
    }
    /**
     * End a session and clean up resources.
     */
    endSession(sessionId) {
        this.sessions.delete(sessionId);
    }
    /**
     * Get current session context (for debugging/inspection).
     */
    getSession(sessionId) {
        return this.sessions.get(sessionId);
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────
    /**
     * Create bootstrap failure response with fail-safe activation.
     */
    createBootstrapFailure(sessionId, errors, auditEvents, options) {
        // Check for cached policy for fail-safe
        // In production, this would attempt to fetch a cached bundle
        const hasCachedPolicy = false; // Placeholder
        const failSafeMode = options.defaultFailSafeMode || (hasCachedPolicy ? FailSafeMode.READ_ONLY_CACHE : FailSafeMode.DENY_ALL);
        this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.FAIL_SAFE_ACTIVATED, {
            mode: failSafeMode,
            reason: errors[0]?.code || "unknown",
        });
        return {
            success: false,
            errors,
            auditEvents,
        };
    }
    /**
     * Normalize policy bundle from various formats.
     */
    normalizePolicyBundle(data) {
        // Ensure all required fields are present
        if (!data.version || !data.contract_id || !data.identity || !data.entitlements) {
            throw new Error("Missing required bundle fields");
        }
        return data;
    }
    /**
     * Decode a JWT payload without signature verification.
     * The bootstrap flow delegates signature and contract validation to PolicyBundleVerifier.
     */
    decodeJwtWithoutVerification(assertion) {
        const segments = assertion.split(".");
        if (segments.length < 2) {
            throw new Error("JWT must contain header and payload segments");
        }
        const [encodedHeader, encodedPayload] = segments;
        const header = JSON.parse(Buffer.from(this.normalizeBase64Url(encodedHeader), "base64").toString("utf8"));
        const payload = JSON.parse(Buffer.from(this.normalizeBase64Url(encodedPayload), "base64").toString("utf8"));
        return { header, payload };
    }
    /**
     * Convert a base64url segment into standard base64 for Buffer decoding.
     */
    normalizeBase64Url(value) {
        const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
        const padding = base64.length % 4;
        if (padding === 0) {
            return base64;
        }
        return `${base64}${"=".repeat(4 - padding)}`;
    }
    /**
     * Validate identity assertion fields.
     */
    validateIdentityAssertion(identity, errors) {
        const requiredFields = ["email", "sub", "roles", "org"];
        for (const field of requiredFields) {
            if (!identity[field]) {
                errors.push({
                    code: "MISSING_IDENTITY_FIELD",
                    message: `Required identity field missing: ${field}`,
                    severity: "critical",
                });
            }
        }
    }
    /**
     * Create session context with policy enforcement.
     */
    createSessionContext(sessionId, bundle, verifiedAt, ttlSeconds, correlationId) {
        const now = Math.floor(Date.now() / 1000);
        return {
            session_id: sessionId,
            user: {
                email: bundle.identity.email,
                sub: bundle.identity.sub,
                roles: bundle.identity.roles,
                org: bundle.identity.org,
            },
            policy: {
                bundle,
                valid: true,
                enforcement_mode: EnforcementMode.STRICT,
                policy_version: bundle.version,
                policy_expires_at: bundle.expires_at,
            },
            authenticated_at: now,
            expires_at: now + ttlSeconds,
            fail_safe_active: false,
            correlation_id: correlationId,
            audit_trail: [],
        };
    }
    /**
     * Check if operation is allowed by policy.
     */
    async checkPolicyAuthorization(session, operation) {
        const repo = this.resolvePolicyRepo(session, operation);
        const action = this.resolvePolicyAction(operation);
        if (!this.policyService) {
            return {
                allowed: session.policy.valid,
                reason: session.policy.valid ? undefined : "Policy invalid",
                repo,
                action,
            };
        }
        const input = {
            actor: session.user.email,
            repo,
            action,
            correlationId: session.correlation_id,
        };
        const decision = this.policyService.simulateDecision(input);
        this.policyService.logDecision(input, decision, "ide-governance");
        return {
            allowed: decision.decision === "allow",
            reason: decision.decision === "allow" ? undefined : decision.reason,
            decision,
            repo,
            action,
        };
    }
    /**
     * Resolve the repository context used for policy decisions.
     */
    resolvePolicyRepo(session, operation) {
        if (operation.resource && operation.resource.trim().length > 0) {
            return operation.resource.trim();
        }
        const entitlementRepo = session.policy.bundle.entitlements.repos[0];
        if (entitlementRepo && entitlementRepo.trim().length > 0) {
            return entitlementRepo.trim();
        }
        return session.user.org;
    }
    /**
     * Map privileged operations into OPA action categories.
     */
    resolvePolicyAction(operation) {
        const operationType = operation.operation_type.toLowerCase();
        if (operationType.includes("read")) {
            return "read";
        }
        if (operationType.includes("admin") || operationType.includes("revoke") || operationType.includes("break_glass")) {
            return "admin";
        }
        return "write";
    }
    /**
     * Detect policy drift (unauthorized local changes).
     */
    detectPolicyDrift(session) {
        // Placeholder for drift detection
        // In production, this would check:
        // - $HOME/.local/share/code-server/User/settings.json
        // - $HOME/.gitconfig
        // - Environment variables against policy
        return {
            drifted: false,
            drifted_fields: [],
            details: {},
        };
    }
    /**
     * Record audit event.
     */
    recordAuditEvent(auditEvents, sessionId, eventType, details) {
        auditEvents.push({
            timestamp: Math.floor(Date.now() / 1000),
            event_type: eventType,
            status: "success",
            details,
            correlation_id: details.correlation_id || sessionId,
        });
    }
    /**
     * Map verification error severity.
     */
    mapVerificationErrorSeverity(errorCode) {
        const criticalErrors = ["INVALID_SIGNATURE", "MISSING_FIELD", "EXPIRED_BUNDLE", "INCOMPATIBLE_VERSION"];
        return criticalErrors.includes(errorCode) ? "critical" : "error";
    }
    /**
     * Generate unique session ID.
     */
    generateSessionId() {
        return `sess-${Date.now()}-${crypto.randomBytes(8).toString("hex")}`;
    }
}
/**
 * Factory function to create enforcer with configured verifier.
 */
export function createSessionBootstrapEnforcer(verifier, policyService) {
    return new SessionBootstrapEnforcer(verifier, policyService);
}
// Export types for consumers
export * from "./types";
//# sourceMappingURL=index.js.map