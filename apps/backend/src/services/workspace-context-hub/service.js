import crypto from "crypto";
const SENSITIVE_KEY_PATTERN = /(token|secret|password|passwd|private|key|credential)/i;
const PROVENANCE_POLICY_VERSION = "ephemeral-provenance-v1";
const PROVENANCE_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const PROVENANCE_CLOCK_SKEW_MS = 5 * 60 * 1000;
/**
 * In-memory workspace context service for multi-repo launch and restore flows.
 *
 * The service enforces ownership and approval rules for shared workspace sets,
 * blocks cross-repo terminal replay unless explicitly confirmed, and redacts
 * sensitive snapshot fields before restore.
 */
export class WorkspaceContextHubService {
    constructor() {
        this.workspaceSets = new Map();
        this.reviewerAccessGrants = new Map();
        this.reviewerAccessTokenIndex = new Map();
        this.restoreMetadataByCorrelationId = new Map();
        this.auditEvents = [];
    }
    registerWorkspaceSet(workspaceSet) {
        const now = Date.now();
        const nextSet = {
            ...workspaceSet,
            shared: workspaceSet.shared ?? false,
            allowedPrincipals: workspaceSet.allowedPrincipals ?? [],
            approvalRequired: workspaceSet.approvalRequired ?? workspaceSet.shared,
            approved: workspaceSet.approved ?? !workspaceSet.shared,
            approvedBy: workspaceSet.approvedBy,
            approvedAt: workspaceSet.approvedAt,
            createdAt: workspaceSet.createdAt ?? now,
            updatedAt: workspaceSet.updatedAt ?? now,
        };
        this.workspaceSets.set(nextSet.id, nextSet);
        this.recordAuditEvent({
            eventType: "workspace_set_registered",
            actor: nextSet.owner,
            workspaceSetId: nextSet.id,
            correlationId: `workspace-${nextSet.id}`,
            reason: `registered workspace set ${nextSet.name}`,
            details: {
                shared: nextSet.shared,
                repositoryCount: nextSet.repositories.length,
            },
        });
        return nextSet;
    }
    exportStateSnapshot() {
        return {
            version: "workspace-context-hub-state/v1",
            exportedAt: Date.now(),
            workspaceSets: [...this.workspaceSets.values()].sort((left, right) => right.updatedAt - left.updatedAt),
        };
    }
    importStateSnapshot(snapshot, actor, correlationId) {
        if (snapshot.version !== "workspace-context-hub-state/v1") {
            throw new Error(`Unsupported workspace context hub snapshot version: ${snapshot.version}`);
        }
        let importedCount = 0;
        for (const workspaceSet of snapshot.workspaceSets) {
            this.workspaceSets.set(workspaceSet.id, workspaceSet);
            importedCount += 1;
        }
        this.recordAuditEvent({
            eventType: "workspace_state_imported",
            actor,
            workspaceSetId: snapshot.workspaceSets[0]?.id ?? "workspace-context-hub",
            correlationId,
            reason: `imported ${importedCount} workspace set records`,
            details: {
                importedCount,
                version: snapshot.version,
                exportedAt: snapshot.exportedAt,
            },
        });
        return importedCount;
    }
    previewWorkspaceLaunch(request, snapshot) {
        const decision = this.evaluateLaunchDecision(request, snapshot);
        if (!decision.workspaceSet) {
            return {
                allowed: false,
                reason: decision.reason,
                blockedTerminalReplayCount: 0,
                redactedFields: [],
                requiresConfirmation: false,
            };
        }
        if (decision.reason) {
            return {
                allowed: false,
                reason: decision.reason,
                workspaceSet: decision.workspaceSet,
                previewSnapshot: decision.sanitized?.snapshot,
                restoreMetadata: decision.restoreMetadata,
                blockedTerminalReplayCount: decision.sanitized?.blockedTerminalReplayCount ?? 0,
                redactedFields: decision.sanitized?.redactedFields ?? [],
                requiresConfirmation: decision.sanitized?.requiresConfirmation ?? false,
            };
        }
        if (decision.sanitized?.requiresConfirmation && !request.confirmCrossRepoReplay) {
            return {
                allowed: false,
                reason: "Cross-repo terminal replay requires explicit confirmation",
                workspaceSet: decision.workspaceSet,
                previewSnapshot: decision.sanitized.snapshot,
                restoreMetadata: decision.restoreMetadata,
                blockedTerminalReplayCount: decision.sanitized.blockedTerminalReplayCount,
                redactedFields: decision.sanitized.redactedFields,
                requiresConfirmation: true,
            };
        }
        return {
            allowed: true,
            workspaceSet: decision.workspaceSet,
            previewSnapshot: decision.sanitized?.snapshot ?? snapshot,
            restoreMetadata: decision.restoreMetadata,
            blockedTerminalReplayCount: decision.sanitized?.blockedTerminalReplayCount ?? 0,
            redactedFields: decision.sanitized?.redactedFields ?? [],
            requiresConfirmation: decision.sanitized?.requiresConfirmation ?? false,
        };
    }
    approveWorkspaceSet(workspaceSetId, approvedBy, correlationId) {
        const workspaceSet = this.requireWorkspaceSet(workspaceSetId);
        const approvedAt = Date.now();
        const nextSet = {
            ...workspaceSet,
            approved: true,
            approvedBy,
            approvedAt,
            updatedAt: approvedAt,
        };
        this.workspaceSets.set(workspaceSetId, nextSet);
        this.recordAuditEvent({
            eventType: "workspace_set_approved",
            actor: approvedBy,
            workspaceSetId,
            correlationId,
            reason: `workspace set approved by ${approvedBy}`,
            details: {
                approvedAt,
            },
        });
        return nextSet;
    }
    launchWorkspace(request, snapshot) {
        const decision = this.evaluateLaunchDecision(request, snapshot);
        if (!decision.workspaceSet) {
            return this.denyLaunch(request, decision.reason ?? "Workspace set not found");
        }
        if (decision.reason) {
            return this.denyLaunch(request, decision.reason, decision.workspaceSet, decision.details);
        }
        if (decision.sanitized?.requiresConfirmation && !request.confirmCrossRepoReplay) {
            return this.denyLaunch(request, "Cross-repo terminal replay requires explicit confirmation", decision.workspaceSet, {
                blockedTerminalReplayCount: decision.sanitized.blockedTerminalReplayCount,
            });
        }
        const { workspaceSet, sanitized, restoreMetadata, activeRepoId } = decision;
        this.restoreMetadataByCorrelationId.set(request.correlationId, restoreMetadata);
        if ((sanitized?.redactedFields.length ?? 0) > 0 || (sanitized?.blockedTerminalReplayCount ?? 0) > 0) {
            this.recordAuditEvent({
                eventType: "workspace_snapshot_redacted",
                actor: request.actor,
                workspaceSetId: workspaceSet.id,
                targetRepoId: request.targetRepoId,
                correlationId: request.correlationId,
                reason: "workspace snapshot redacted before restore",
                details: {
                    blockedTerminalReplayCount: sanitized?.blockedTerminalReplayCount ?? 0,
                    redactedFields: sanitized?.redactedFields ?? [],
                    requiresConfirmation: sanitized?.requiresConfirmation ?? false,
                },
            });
        }
        const auditEvent = this.recordAuditEvent({
            eventType: "workspace_launch_allowed",
            actor: request.actor,
            workspaceSetId: workspaceSet.id,
            targetRepoId: request.targetRepoId,
            correlationId: request.correlationId,
            reason: "workspace launch authorized",
            details: {
                activeRepoId,
                repositoryCount: workspaceSet.repositories.length,
                blockedTerminalReplayCount: restoreMetadata.blockedTerminalReplayCount,
                sessionFingerprint: restoreMetadata.sessionFingerprint,
                provenance: restoreMetadata.provenance,
            },
        });
        return {
            allowed: true,
            workspaceSet,
            sanitizedSnapshot: sanitized?.snapshot ?? snapshot,
            restoreMetadata,
            auditEvent,
        };
    }
    getWorkspaceSet(workspaceSetId) {
        return this.workspaceSets.get(workspaceSetId);
    }
    listWorkspaceSetsForActor(actor, includeOwned = true) {
        const normalizedActor = actor.trim().toLowerCase();
        return [...this.workspaceSets.values()]
            .filter((workspaceSet) => {
            const ownerMatch = workspaceSet.owner.toLowerCase() === normalizedActor;
            if (ownerMatch) {
                return includeOwned;
            }
            if (!workspaceSet.shared) {
                return false;
            }
            const principals = new Set((workspaceSet.allowedPrincipals ?? []).map((principal) => principal.toLowerCase()));
            if (principals.size === 0) {
                return true;
            }
            return principals.has(normalizedActor);
        })
            .sort((left, right) => right.updatedAt - left.updatedAt);
    }
    getRestoreMetadataByCorrelationId(correlationId) {
        return this.restoreMetadataByCorrelationId.get(correlationId);
    }
    getAuditEvents(workspaceSetId) {
        return workspaceSetId
            ? this.auditEvents.filter((event) => event.workspaceSetId === workspaceSetId)
            : [...this.auditEvents];
    }
    issueReviewerAccessLink(params) {
        const workspaceSet = this.requireWorkspaceSet(params.workspaceSetId);
        const issuedAt = Date.now();
        const expiresAt = issuedAt + Math.max(1, params.ttlMs ?? 60 * 60 * 1000);
        const token = crypto.randomBytes(32).toString("hex");
        const tokenHash = this.hashReviewerToken(token);
        const grant = {
            grantId: crypto.randomUUID(),
            workspaceSetId: workspaceSet.id,
            sessionId: params.sessionId,
            reviewer: params.reviewer,
            permission: params.permission,
            issuedBy: params.actor,
            issuedAt,
            expiresAt,
            oneTimeUse: params.oneTimeUse ?? true,
            tokenHash,
        };
        this.reviewerAccessGrants.set(grant.grantId, grant);
        this.reviewerAccessTokenIndex.set(tokenHash, grant.grantId);
        this.recordAuditEvent({
            eventType: "workspace_reviewer_link_issued",
            actor: params.actor,
            workspaceSetId: workspaceSet.id,
            sessionId: params.sessionId,
            correlationId: params.correlationId,
            reason: `issued ${params.permission} reviewer link for ${params.reviewer}`,
            details: {
                grantId: grant.grantId,
                reviewer: params.reviewer,
                permission: params.permission,
                expiresAt,
                oneTimeUse: grant.oneTimeUse,
            },
        });
        return { token, grant };
    }
    resolveReviewerAccessLink(token, sessionId, requiredPermission = "view-only", correlationId = `reviewer-access-${sessionId}`) {
        const grantId = this.reviewerAccessTokenIndex.get(this.hashReviewerToken(token));
        if (!grantId) {
            return undefined;
        }
        const grant = this.reviewerAccessGrants.get(grantId);
        if (!grant || grant.sessionId !== sessionId) {
            return undefined;
        }
        if (this.isReviewerAccessInvalid(grant, requiredPermission)) {
            return undefined;
        }
        const consumedAt = Date.now();
        if (grant.oneTimeUse) {
            const updated = {
                ...grant,
                consumedAt,
            };
            this.reviewerAccessGrants.set(grant.grantId, updated);
            this.recordAuditEvent({
                eventType: "workspace_reviewer_link_consumed",
                actor: grant.reviewer,
                workspaceSetId: grant.workspaceSetId,
                sessionId: grant.sessionId,
                correlationId,
                reason: `reviewer link consumed for ${grant.reviewer}`,
                details: {
                    grantId: grant.grantId,
                    permission: grant.permission,
                    oneTimeUse: true,
                },
            });
            return updated;
        }
        this.recordAuditEvent({
            eventType: "workspace_reviewer_link_consumed",
            actor: grant.reviewer,
            workspaceSetId: grant.workspaceSetId,
            sessionId: grant.sessionId,
            correlationId,
            reason: `reviewer link consumed for ${grant.reviewer}`,
            details: {
                grantId: grant.grantId,
                permission: grant.permission,
                oneTimeUse: false,
            },
        });
        return grant;
    }
    revokeReviewerAccessLink(grantId, actor, correlationId, reason = "manual revocation") {
        const grant = this.reviewerAccessGrants.get(grantId);
        if (!grant) {
            throw new Error(`Reviewer access grant not found: ${grantId}`);
        }
        const updated = {
            ...grant,
            revokedAt: Date.now(),
            revokedReason: reason,
        };
        this.reviewerAccessGrants.set(grantId, updated);
        this.reviewerAccessTokenIndex.delete(grant.tokenHash);
        this.recordAuditEvent({
            eventType: "workspace_reviewer_link_revoked",
            actor,
            workspaceSetId: grant.workspaceSetId,
            sessionId: grant.sessionId,
            correlationId,
            reason: `reviewer link revoked: ${reason}`,
            details: {
                grantId,
                reviewer: grant.reviewer,
                permission: grant.permission,
            },
        });
        return updated;
    }
    getReviewerAccessGrants(workspaceSetId) {
        const grants = [...this.reviewerAccessGrants.values()];
        return workspaceSetId ? grants.filter((grant) => grant.workspaceSetId === workspaceSetId) : grants;
    }
    evaluateLaunchDecision(request, snapshot) {
        const workspaceSet = this.workspaceSets.get(request.workspaceSetId);
        if (!workspaceSet) {
            return {
                reason: "Workspace set not found",
                restoreMetadata: {
                    workspaceSetId: request.workspaceSetId,
                    owner: "",
                    activeRepoId: request.targetRepoId || snapshot?.activeRepoId || "",
                    repositoryCount: 0,
                    terminalCount: snapshot?.terminals.length ?? 0,
                    blockedTerminalReplayCount: 0,
                    redactedFields: [],
                    requiresConfirmation: false,
                    generatedAt: Date.now(),
                },
                activeRepoId: request.targetRepoId || snapshot?.activeRepoId || "",
            };
        }
        const provenanceError = this.validateLaunchProvenance(request.provenance);
        const authorizationError = this.validateLaunchAuthorization(workspaceSet, request);
        const sanitized = snapshot ? this.sanitizeSnapshot(workspaceSet, snapshot, request) : undefined;
        const activeRepoId = request.targetRepoId || snapshot?.activeRepoId || workspaceSet.repositories[0]?.repoId || "";
        const sessionFingerprint = request.provenance
            ? this.computeSessionFingerprint(workspaceSet, activeRepoId, request.provenance, snapshot)
            : undefined;
        const restoreMetadata = {
            workspaceSetId: workspaceSet.id,
            owner: workspaceSet.owner,
            activeRepoId,
            repositoryCount: workspaceSet.repositories.length,
            terminalCount: sanitized?.snapshot.terminals.length ?? snapshot?.terminals.length ?? 0,
            blockedTerminalReplayCount: sanitized?.blockedTerminalReplayCount ?? 0,
            redactedFields: sanitized?.redactedFields ?? [],
            requiresConfirmation: sanitized?.requiresConfirmation ?? false,
            sessionFingerprint,
            provenance: request.provenance,
            generatedAt: Date.now(),
        };
        return {
            workspaceSet,
            reason: provenanceError ?? authorizationError,
            sanitized,
            restoreMetadata,
            activeRepoId,
        };
    }
    validateLaunchProvenance(provenance) {
        if (!provenance) {
            return "Launch requires a provenance attestation";
        }
        if (provenance.verificationResult !== "verified") {
            return "Provenance attestation must be verified before launch";
        }
        if (!/^sha256:[a-f0-9]{64}$/.test(provenance.imageDigest)) {
            return `Invalid provenance image digest ${provenance.imageDigest}`;
        }
        if (!provenance.attestationRef.trim()) {
            return "Provenance attestation reference is required";
        }
        if (!provenance.signerIdentity.trim()) {
            return "Provenance signer identity is required";
        }
        if (provenance.policyVersion !== PROVENANCE_POLICY_VERSION) {
            return `Unsupported provenance policy version ${provenance.policyVersion}`;
        }
        const now = Date.now();
        if (provenance.verificationTimestamp > now + PROVENANCE_CLOCK_SKEW_MS) {
            return "Provenance verification timestamp is in the future";
        }
        if (now - provenance.verificationTimestamp > PROVENANCE_MAX_AGE_MS) {
            return "Provenance attestation is stale";
        }
        return undefined;
    }
    computeSessionFingerprint(workspaceSet, activeRepoId, provenance, snapshot) {
        const manifest = {
            workspaceSetId: workspaceSet.id,
            owner: workspaceSet.owner,
            org: workspaceSet.org,
            activeRepoId,
            repositoryIds: [...workspaceSet.repositories].map((repo) => repo.repoId).sort(),
            openFiles: [...(snapshot?.openFiles ?? [])].sort(),
            terminalCount: snapshot?.terminals.length ?? 0,
            provenance: {
                imageDigest: provenance.imageDigest,
                attestationRef: provenance.attestationRef,
                signerIdentity: provenance.signerIdentity,
                verificationTimestamp: provenance.verificationTimestamp,
                verificationResult: provenance.verificationResult,
                policyVersion: provenance.policyVersion,
            },
        };
        return `sha256:${crypto.createHash("sha256").update(JSON.stringify(manifest)).digest("hex")}`;
    }
    validateLaunchAuthorization(workspaceSet, request) {
        const targetRepoId = request.targetRepoId;
        if (targetRepoId && !workspaceSet.repositories.some((repo) => repo.repoId === targetRepoId)) {
            return `Repository ${targetRepoId} is not part of workspace set ${workspaceSet.id}`;
        }
        if (workspaceSet.shared) {
            if (workspaceSet.approvalRequired && !workspaceSet.approved && request.actor !== workspaceSet.owner) {
                return "Workspace set requires approval before launch";
            }
            const allowedPrincipals = new Set(workspaceSet.allowedPrincipals ?? []);
            if (request.actor !== workspaceSet.owner && allowedPrincipals.size > 0 && !allowedPrincipals.has(request.actor)) {
                return `Actor ${request.actor} is not allowed to launch shared workspace set ${workspaceSet.id}`;
            }
        }
        return undefined;
    }
    hashReviewerToken(token) {
        return crypto.createHash("sha256").update(token).digest("hex");
    }
    isReviewerAccessInvalid(grant, requiredPermission, now = Date.now()) {
        const permissionRank = {
            "view-only": 0,
            "approve-only": 1,
        };
        if (grant.revokedAt) {
            return true;
        }
        if (grant.expiresAt <= now) {
            return true;
        }
        if (grant.oneTimeUse && grant.consumedAt) {
            return true;
        }
        return permissionRank[grant.permission] < permissionRank[requiredPermission];
    }
    sanitizeSnapshot(workspaceSet, snapshot, request) {
        const targetRepoId = request.targetRepoId || snapshot.activeRepoId;
        const redactedFields = [];
        let blockedTerminalReplayCount = 0;
        let requiresConfirmation = false;
        const terminals = [];
        for (const terminal of snapshot.terminals) {
            const sameRepo = terminal.repoId === targetRepoId;
            if (!sameRepo) {
                blockedTerminalReplayCount += 1;
                requiresConfirmation = true;
                if (!request.confirmCrossRepoReplay) {
                    continue;
                }
            }
            const redactedEnv = this.redactSecretValues(terminal.env, `terminals.${terminal.id}.env`, redactedFields);
            const redactedCommand = this.redactCommand(terminal.command, terminal.id, redactedFields);
            terminals.push({
                ...terminal,
                command: redactedCommand,
                env: redactedEnv,
            });
        }
        const metadata = this.redactMetadata(snapshot.metadata, redactedFields);
        return {
            snapshot: {
                ...snapshot,
                terminals,
                metadata,
            },
            redactedFields,
            blockedTerminalReplayCount,
            requiresConfirmation,
        };
    }
    redactMetadata(metadata, redactedFields) {
        if (!metadata) {
            return metadata;
        }
        const nextMetadata = {};
        for (const [key, value] of Object.entries(metadata)) {
            if (SENSITIVE_KEY_PATTERN.test(key)) {
                redactedFields.push(`metadata.${key}`);
                nextMetadata[key] = "[redacted]";
                continue;
            }
            nextMetadata[key] = value;
        }
        return nextMetadata;
    }
    redactSecretValues(env, prefix, redactedFields) {
        if (!env) {
            return env;
        }
        const nextEnv = {};
        for (const [key, value] of Object.entries(env)) {
            if (SENSITIVE_KEY_PATTERN.test(key)) {
                redactedFields.push(`${prefix}.${key}`);
                nextEnv[key] = "[redacted]";
                continue;
            }
            nextEnv[key] = value;
        }
        return nextEnv;
    }
    redactCommand(command, terminalId, redactedFields) {
        if (!command) {
            return command;
        }
        const looksSensitive = /(--token|--password|secret=|password=|token=|ssh -i)/i.test(command);
        if (!looksSensitive) {
            return command;
        }
        redactedFields.push(`terminals.${terminalId}.command`);
        return "[redacted]";
    }
    denyLaunch(request, reason, workspaceSet, details) {
        const auditEvent = this.recordAuditEvent({
            eventType: "workspace_launch_denied",
            actor: request.actor,
            workspaceSetId: request.workspaceSetId,
            targetRepoId: request.targetRepoId,
            correlationId: request.correlationId,
            reason,
            details,
        });
        return {
            allowed: false,
            reason,
            workspaceSet,
            auditEvent,
        };
    }
    requireWorkspaceSet(workspaceSetId) {
        const workspaceSet = this.workspaceSets.get(workspaceSetId);
        if (!workspaceSet) {
            throw new Error(`Workspace set not found: ${workspaceSetId}`);
        }
        return workspaceSet;
    }
    recordAuditEvent(event) {
        const auditEvent = {
            ...event,
            eventId: crypto.randomUUID(),
            timestamp: Date.now(),
        };
        this.auditEvents.push(auditEvent);
        return auditEvent;
    }
}
export function createWorkspaceContextHubService() {
    return new WorkspaceContextHubService();
}
//# sourceMappingURL=service.js.map