/**
 * Auto-merge on Code Review Approval Service
 * @file        apps/backend/src/services/auto-merge/auto-merge-service.ts
 * @module      services/auto-merge
 * @description Automatic PR merging with policies, conditions, and approval workflows
 */
import { EventEmitter } from 'events';
/**
 * Auto-merge on Code Review Approval Service
 *
 * Manages automatic PR merging with:
 * - Approval-based merge policies
 * - Configurable merge conditions and exceptions
 * - Merge strategy selection
 * - Status check validation
 * - SOC2-compliant audit logging
 * - Real-time event notifications
 */
export class AutoMergeService extends EventEmitter {
    constructor() {
        super();
        this.policies = new Map();
        this.policiesByRepo = new Map();
        this.autoMergeRequests = new Map();
        this.exceptions = new Map();
        this.exceptionsByPolicy = new Map();
        this.auditLogs = new Map();
        this.mergeAttempts = new Map();
        this.config = {
            maxPolicies: 100,
            maxAutoMergeRequests: 1000,
            maxMergeAttempts: 3,
            defaultMergeDelay: 5000,
            maxAutoMergeDelay: 3600000,
            enableNotifications: true,
            enableSlackNotifications: false,
            enableEmailNotifications: true,
            maxAuditLogSize: 10000,
            retentionDays: 365,
        };
        this.initialize();
    }
    /**
     * Get or create service instance
     */
    static getInstance(config) {
        if (!AutoMergeService.instance) {
            AutoMergeService.instance = new AutoMergeService();
        }
        if (config) {
            AutoMergeService.instance.updateConfig(config, 'system', '127.0.0.1', 'node');
        }
        return AutoMergeService.instance;
    }
    /**
     * Reset instance for testing
     */
    static reset() {
        if (AutoMergeService.instance) {
            AutoMergeService.instance.shutdown();
        }
        AutoMergeService.instance = null;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'auto-merge', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Create policy
     */
    createPolicy(policy, createdBy, ipAddress, userAgent) {
        try {
            const policyId = `policy-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const newPolicy = {
                id: policyId,
                repoId: policy.repoId || '',
                name: policy.name || 'Untitled Policy',
                description: policy.description,
                enabled: policy.enabled !== false,
                createdAt: Date.now(),
                updatedAt: Date.now(),
                createdBy,
                requiredApprovals: policy.requiredApprovals || 2,
                requireCodeOwnerApproval: policy.requireCodeOwnerApproval || false,
                dismissStaleReviews: policy.dismissStaleReviews || false,
                requireUpToDateBranch: policy.requireUpToDateBranch || true,
                mergeStrategy: policy.mergeStrategy || 'merge',
                deleteHeadBranch: policy.deleteHeadBranch !== false,
                commitMessageTemplate: policy.commitMessageTemplate,
                autoMergeOnApprovalCount: policy.autoMergeOnApprovalCount || true,
                autoMergeOnLabelAdd: policy.autoMergeOnLabelAdd || false,
                triggerLabels: policy.triggerLabels || [],
                conditions: policy.conditions || [],
                exceptions: policy.exceptions || [],
                autoMergeDelay: policy.autoMergeDelay || this.config.defaultMergeDelay,
                mergeWindowStart: policy.mergeWindowStart,
                mergeWindowEnd: policy.mergeWindowEnd,
                requiredStatusChecks: policy.requiredStatusChecks || [],
                allowFailureOnSpecificChecks: policy.allowFailureOnSpecificChecks,
            };
            this.policies.set(policyId, newPolicy);
            if (!this.policiesByRepo.has(policy.repoId || '')) {
                this.policiesByRepo.set(policy.repoId || '', new Set());
            }
            this.policiesByRepo.get(policy.repoId || '').add(policyId);
            this.emit('policy-created', {
                data_object: { policyId, repoId: policy.repoId, createdBy: createdBy.userId },
                timestamp: Date.now(),
            });
            this.logAudit(createdBy.userId, createdBy.userEmail, ipAddress, userAgent, 'policy-created', policyId, '', { name: policy.name, repoId: policy.repoId });
            return { success: true, policyId };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Update policy
     */
    updatePolicy(policyId, updates, updatedBy, ipAddress, userAgent) {
        try {
            const policy = this.policies.get(policyId);
            if (!policy) {
                return { success: false, error: 'Policy not found' };
            }
            Object.assign(policy, updates, { updatedAt: Date.now() });
            this.emit('policy-updated', {
                data_object: { policyId, updatedBy: updatedBy.userId },
                timestamp: Date.now(),
            });
            this.logAudit(updatedBy.userId, updatedBy.userEmail, ipAddress, userAgent, 'policy-updated', policyId, '', updates);
            return { success: true, policy };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Delete policy
     */
    deletePolicy(policyId, deletedBy, ipAddress, userAgent) {
        try {
            const policy = this.policies.get(policyId);
            if (!policy) {
                return { success: false, error: 'Policy not found' };
            }
            this.policies.delete(policyId);
            this.policiesByRepo.get(policy.repoId)?.delete(policyId);
            this.emit('policy-deleted', {
                data_object: { policyId, deletedBy: deletedBy.userId },
                timestamp: Date.now(),
            });
            this.logAudit(deletedBy.userId, deletedBy.userEmail, ipAddress, userAgent, 'policy-deleted', policyId, '', { repoId: policy.repoId });
            return { success: true };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Get policy
     */
    getPolicy(policyId) {
        try {
            const policy = this.policies.get(policyId);
            if (!policy) {
                return { success: false, error: 'Policy not found' };
            }
            return { success: true, policy };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * List policies
     */
    listPolicies(repoId) {
        try {
            const policyIds = this.policiesByRepo.get(repoId) || new Set();
            const policies = Array.from(policyIds)
                .map((id) => this.policies.get(id))
                .filter((p) => p !== undefined);
            return { success: true, policies };
        }
        catch (error) {
            return { success: false, policies: [], error: error.message };
        }
    }
    /**
     * Evaluate merge
     */
    evaluateMerge(pr, policyId) {
        try {
            const policy = this.policies.get(policyId);
            if (!policy) {
                return {
                    canAutoMerge: false,
                    policyMatched: false,
                    approvalsSatisfied: false,
                    statusChecksPassed: false,
                    conditionsMet: false,
                    blockingReasons: ['Policy not found'],
                    warnings: [],
                    recommendations: [],
                };
            }
            const blockingReasons = [];
            const warnings = [];
            const recommendations = [];
            // Check if enabled
            if (!policy.enabled) {
                blockingReasons.push('Policy is disabled');
            }
            // Check approvals
            const approvalsSatisfied = pr.approvalCount >= policy.requiredApprovals;
            if (!approvalsSatisfied) {
                blockingReasons.push(`Requires ${policy.requiredApprovals} approvals, has ${pr.approvalCount}`);
            }
            // Check code owner approval
            if (policy.requireCodeOwnerApproval) {
                const hasCodeOwnerApproval = pr.reviewers.some((r) => r.isCodeOwner && r.state === 'approved');
                if (!hasCodeOwnerApproval) {
                    blockingReasons.push('Code owner approval required');
                }
            }
            // Check branch status
            if (policy.requireUpToDateBranch && pr.mergeableState === 'behind') {
                blockingReasons.push('Branch is behind target');
                recommendations.push('Rebase or update branch');
            }
            // Check status checks
            const statusChecksPassed = policy.requiredStatusChecks.every((checkName) => {
                const check = pr.requiredStatusChecks.find((c) => c.name === checkName);
                return check && (check.status === 'success' || check.status === 'skipped');
            });
            if (!statusChecksPassed) {
                blockingReasons.push('Required status checks did not pass');
            }
            // Check conditions
            const conditionsMet = policy.conditions.length === 0 || this.evaluateConditions(policy, pr);
            if (policy.conditions.length > 0 && !conditionsMet) {
                blockingReasons.push('Merge conditions not met');
            }
            // Check exceptions
            const hasBlockingException = this.hasBlockingException(policyId, pr);
            if (hasBlockingException) {
                blockingReasons.push('Blocking exception exists');
            }
            const canAutoMerge = blockingReasons.length === 0 && policy.enabled && approvalsSatisfied;
            return {
                canAutoMerge,
                policyMatched: true,
                approvalsSatisfied,
                statusChecksPassed,
                conditionsMet,
                blockingReasons,
                warnings,
                recommendations,
                matchedPolicy: policy,
                estimatedMergeTime: canAutoMerge ? Date.now() + policy.autoMergeDelay : undefined,
            };
        }
        catch (error) {
            return {
                canAutoMerge: false,
                policyMatched: false,
                approvalsSatisfied: false,
                statusChecksPassed: false,
                conditionsMet: false,
                blockingReasons: [error.message],
                warnings: [],
                recommendations: [],
            };
        }
    }
    /**
     * Request auto-merge
     */
    requestAutoMerge(prId, policyId, requestedBy, ipAddress, userAgent) {
        try {
            const requestId = `merge-req-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const mergeRequest = {
                id: requestId,
                prId,
                policyId,
                requestedBy,
                requestedAt: Date.now(),
                status: 'pending',
                statusUpdatedAt: Date.now(),
                attempt: 0,
            };
            this.autoMergeRequests.set(requestId, mergeRequest);
            this.emit('merge-requested', {
                data_object: {
                    requestId,
                    prId,
                    policyId,
                    requestedBy: requestedBy.userId,
                },
                timestamp: Date.now(),
            });
            this.logAudit(requestedBy.userId, requestedBy.userEmail, ipAddress, userAgent, 'merge-attempted', policyId, prId, { requestId });
            return { success: true, requestId };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Approve auto-merge
     */
    approveAutoMerge(requestId, approvedBy, ipAddress, userAgent) {
        try {
            const request = this.autoMergeRequests.get(requestId);
            if (!request) {
                return { success: false, error: 'Request not found' };
            }
            request.status = 'approved';
            request.statusUpdatedAt = Date.now();
            this.emit('merge-approved', {
                data_object: {
                    requestId,
                    prId: request.prId,
                    approvedBy: approvedBy.userId,
                },
                timestamp: Date.now(),
            });
            this.logAudit(approvedBy.userId, approvedBy.userEmail, ipAddress, userAgent, 'merge-approved', request.policyId, request.prId, { requestId });
            return { success: true, request };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Schedule merge
     */
    scheduleMerge(requestId, scheduledAt, scheduledBy, ipAddress, userAgent) {
        try {
            const request = this.autoMergeRequests.get(requestId);
            if (!request) {
                return { success: false, error: 'Request not found' };
            }
            request.status = 'scheduled';
            request.statusUpdatedAt = Date.now();
            this.emit('merge-scheduled', {
                data_object: {
                    requestId,
                    prId: request.prId,
                    scheduledAt,
                    scheduledBy: scheduledBy.userId,
                },
                timestamp: Date.now(),
            });
            this.logAudit(scheduledBy.userId, scheduledBy.userEmail, ipAddress, userAgent, 'merge-scheduled', request.policyId, request.prId, { requestId, scheduledAt });
            return { success: true, request };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Execute merge
     */
    executeMerge(requestId, mergeBy, ipAddress, userAgent) {
        try {
            const request = this.autoMergeRequests.get(requestId);
            if (!request) {
                return { success: false, error: 'Request not found' };
            }
            const attempts = this.mergeAttempts.get(requestId) || 0;
            if (attempts >= this.config.maxMergeAttempts) {
                request.status = 'failed';
                request.errorMessage = 'Max merge attempts exceeded';
                return {
                    success: false,
                    error: 'Max merge attempts exceeded',
                };
            }
            request.status = 'merging';
            request.statusUpdatedAt = Date.now();
            request.attempt = attempts + 1;
            request.lastAttemptedAt = Date.now();
            const mergeCommitId = `commit-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            request.status = 'merged';
            request.mergeCommitId = mergeCommitId;
            request.mergedAt = Date.now();
            this.mergeAttempts.set(requestId, attempts + 1);
            this.emit('merge-successful', {
                data_object: {
                    requestId,
                    prId: request.prId,
                    mergeCommitId,
                    mergedBy: mergeBy.userId,
                },
                timestamp: Date.now(),
            });
            this.logAudit(mergeBy.userId, mergeBy.userEmail, ipAddress, userAgent, 'merge-successful', request.policyId, request.prId, { requestId, mergeCommitId, attempts: request.attempt });
            return { success: true, mergeCommitId };
        }
        catch (error) {
            const request = this.autoMergeRequests.get(requestId);
            if (request) {
                request.status = 'failed';
                request.errorMessage = error.message;
            }
            return { success: false, error: error.message };
        }
    }
    /**
     * Cancel auto-merge
     */
    cancelAutoMerge(requestId, cancelledBy, reason, ipAddress, userAgent) {
        try {
            const request = this.autoMergeRequests.get(requestId);
            if (!request) {
                return { success: false, error: 'Request not found' };
            }
            request.status = 'cancelled';
            request.statusUpdatedAt = Date.now();
            request.reason = reason;
            this.emit('merge-cancelled', {
                data_object: {
                    requestId,
                    prId: request.prId,
                    cancelledBy: cancelledBy.userId,
                    reason,
                },
                timestamp: Date.now(),
            });
            this.logAudit(cancelledBy.userId, cancelledBy.userEmail, ipAddress, userAgent, 'merge-attempted', request.policyId, request.prId, { requestId, reason });
            return { success: true, request };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Add exception
     */
    addException(policyId, exception, addedBy, ipAddress, userAgent) {
        try {
            const exceptionId = `exc-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            exception.id = exceptionId;
            exception.policyId = policyId;
            this.exceptions.set(exceptionId, exception);
            if (!this.exceptionsByPolicy.has(policyId)) {
                this.exceptionsByPolicy.set(policyId, new Set());
            }
            this.exceptionsByPolicy.get(policyId).add(exceptionId);
            this.emit('exception-added', {
                data_object: {
                    exceptionId,
                    policyId,
                    type: exception.type,
                    addedBy: addedBy.userId,
                },
                timestamp: Date.now(),
            });
            this.logAudit(addedBy.userId, addedBy.userEmail, ipAddress, userAgent, 'exception-added', policyId, '', { exceptionId, type: exception.type });
            return { success: true, exceptionId };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Remove exception
     */
    removeException(policyId, exceptionId, removedBy, ipAddress, userAgent) {
        try {
            this.exceptions.delete(exceptionId);
            this.exceptionsByPolicy.get(policyId)?.delete(exceptionId);
            this.emit('exception-removed', {
                data_object: {
                    exceptionId,
                    policyId,
                    removedBy: removedBy.userId,
                },
                timestamp: Date.now(),
            });
            this.logAudit(removedBy.userId, removedBy.userEmail, ipAddress, userAgent, 'exception-removed', policyId, '', { exceptionId });
            return { success: true };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Get statistics
     */
    getStatistics() {
        const activePolicies = Array.from(this.policies.values()).filter((p) => p.enabled).length;
        const allRequests = Array.from(this.autoMergeRequests.values());
        const successfulMerges = allRequests.filter((r) => r.status === 'merged').length;
        const failedMerges = allRequests.filter((r) => r.status === 'failed').length;
        const pendingMerges = allRequests.filter((r) => ['pending', 'approved', 'scheduled', 'merging'].includes(r.status)).length;
        const mergeTimes = allRequests
            .filter((r) => r.mergedAt && r.requestedAt)
            .map((r) => (r.mergedAt - r.requestedAt) / 1000); // seconds
        const averageMergeTime = mergeTimes.length > 0 ? mergeTimes.reduce((a, b) => a + b, 0) / mergeTimes.length : 0;
        const successRate = allRequests.length > 0
            ? Math.round((successfulMerges / allRequests.length) * 10000) / 10000
            : 0;
        const strategies = Array.from(this.policies.values()).map((p) => p.mergeStrategy);
        const strategyCount = new Map();
        strategies.forEach((s) => {
            strategyCount.set(s, (strategyCount.get(s) || 0) + 1);
        });
        const mostUsedStrategy = Array.from(strategyCount.entries()).sort((a, b) => b[1] - a[1])[0]?.[0] || 'merge';
        return {
            totalPolicies: this.policies.size,
            activePolicies,
            totalAutoMergeRequests: allRequests.length,
            successfulMerges,
            failedMerges,
            pendingMerges,
            averageMergeTime: Math.round(averageMergeTime * 100) / 100,
            successRate,
            mostUsedMergeStrategy: mostUsedStrategy,
            policyEffectiveness: new Map(),
        };
    }
    /**
     * Update configuration
     */
    updateConfig(config, userId, ipAddress, userAgent) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', {
            data_object: { userId, config },
            timestamp: Date.now(),
        });
        this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'policy-updated', '', '', {
            configUpdate: config,
        });
    }
    /**
     * Evaluate conditions
     */
    evaluateConditions(policy, pr) {
        if (policy.conditions.length === 0)
            return true;
        return policy.conditions.every((condition) => {
            switch (condition.type) {
                case 'label-required':
                    return pr.labels.includes(condition.value);
                case 'label-excluded':
                    return !pr.labels.includes(condition.value);
                case 'title-pattern':
                    return new RegExp(condition.value).test(pr.title);
                default:
                    return true;
            }
        });
    }
    /**
     * Check for blocking exception
     */
    hasBlockingException(policyId, pr) {
        const exceptionIds = this.exceptionsByPolicy.get(policyId) || new Set();
        return Array.from(exceptionIds).some((excId) => {
            const exc = this.exceptions.get(excId);
            return exc && exc.type === 'block-merge' && exc.action === 'deny';
        });
    }
    /**
     * Log audit entry
     */
    logAudit(userId, userEmail, ipAddress, userAgent, operation, policyId, prId, details) {
        const entry = {
            timestamp: Date.now(),
            userId,
            userEmail,
            ipAddress,
            userAgent,
            operation,
            policyId,
            prId,
            status: 'success',
            details: new Map(Object.entries(details)),
        };
        if (!this.auditLogs.has(userId)) {
            this.auditLogs.set(userId, []);
        }
        const logs = this.auditLogs.get(userId);
        logs.push(entry);
        if (logs.length > this.config.maxAuditLogSize) {
            logs.splice(0, logs.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', {
            data_object: { userId, operation, status: 'success' },
            timestamp: Date.now(),
        });
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.policies.clear();
        this.policiesByRepo.clear();
        this.autoMergeRequests.clear();
        this.exceptions.clear();
        this.exceptionsByPolicy.clear();
        this.auditLogs.clear();
        this.mergeAttempts.clear();
        this.emit('shutdown', {
            data_object: { service: 'auto-merge', status: 'shutdown' },
            timestamp: Date.now(),
        });
        this.removeAllListeners();
    }
}
//# sourceMappingURL=auto-merge-service.js.map