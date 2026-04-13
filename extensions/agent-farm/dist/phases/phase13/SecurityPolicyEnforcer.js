"use strict";
/**
 * Security Policy Enforcer
 *
 * Policy-based access control and enforcement with:
 * - Fine-grained access control (ABAC)
 * - Policy evaluation and validation
 * - Attribute-based conditions
 * - Policy conflict resolution
 * - Audit logging of policy decisions
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.SecurityPolicyEnforcer = exports.PolicyAction = void 0;
var PolicyAction;
(function (PolicyAction) {
    PolicyAction["ALLOW"] = "allow";
    PolicyAction["DENY"] = "deny";
    PolicyAction["CHALLENGE"] = "challenge";
})(PolicyAction || (exports.PolicyAction = PolicyAction = {}));
/**
 * SecurityPolicyEnforcer - Attribute-Based Access Control (ABAC)
 *
 * Features:
 * - Fine-grained access control based on attributes
 * - Policy prioritization
 * - Condition evaluation
 * - Conflict resolution
 * - Audit logging
 * - Real-time policy updates
 */
class SecurityPolicyEnforcer {
    constructor() {
        this.policies = new Map();
        this.policyDecisions = [];
        this.maxDecisionHistorySize = 100000;
        this.policyVersion = 0;
        this.lastPolicyUpdate = new Date();
        this.registerDefaultPolicies();
    }
    /**
     * Register default security policies
     */
    registerDefaultPolicies() {
        // Policy 1: Deny all by default (zero-trust)
        this.addPolicy({
            policyId: 'policy_default_deny',
            name: 'Default Deny All',
            description: 'Deny all access unless explicitly allowed',
            effect: 'deny',
            principal: { type: 'any', identifiers: ['*'] },
            action: ['*'],
            resource: { type: 'all', resources: ['*'] },
            priority: 0, // Lowest priority
            enabled: true,
            createdAt: new Date(),
            updatedAt: new Date(),
            createdBy: 'system'
        });
        // Policy 2: Allow authenticated users to read public resources
        this.addPolicy({
            policyId: 'policy_public_read',
            name: 'Public Resource Read Access',
            description: 'Allow authenticated users to read public resources',
            effect: 'allow',
            principal: { type: 'user', identifiers: ['*'] },
            action: ['read'],
            resource: { type: 'pattern', resources: ['public/*'] },
            priority: 50,
            enabled: true,
            createdAt: new Date(),
            updatedAt: new Date(),
            createdBy: 'system'
        });
        // Policy 3: Restrict administrative actions to admins only
        this.addPolicy({
            policyId: 'policy_admin_only',
            name: 'Administrative Actions',
            description: 'Only administrators can perform admin actions',
            effect: 'allow',
            principal: { type: 'role', identifiers: ['admin'] },
            action: ['create', 'delete', 'escalate', 'configure'],
            resource: { type: 'all', resources: ['*'] },
            priority: 100, // High priority
            enabled: true,
            createdAt: new Date(),
            updatedAt: new Date(),
            createdBy: 'system'
        });
        // Policy 4: Deny data exfiltration
        this.addPolicy({
            policyId: 'policy_prevent_exfiltration',
            name: 'Prevent Data Exfiltration',
            description: 'Block large data exports',
            effect: 'deny',
            principal: { type: 'any', identifiers: ['*'] },
            action: ['export', 'download'],
            resource: { type: 'pattern', resources: ['sensitive/*', 'pii/*', 'financial/*'] },
            condition: {
                type: 'and',
                conditions: [
                    { attribute: 'dataSize', operator: 'greater_than', value: 100 * 1024 * 1024 } // > 100 MB
                ]
            },
            priority: 95, // Very high priority
            enabled: true,
            createdAt: new Date(),
            updatedAt: new Date(),
            createdBy: 'system'
        });
    }
    /**
     * Add a new policy
     */
    addPolicy(policy) {
        this.policies.set(policy.policyId, policy);
        this.policyVersion++;
        this.lastPolicyUpdate = new Date();
    }
    /**
     * Update an existing policy
     */
    updatePolicy(policyId, updates) {
        const policy = this.policies.get(policyId);
        if (!policy) {
            return false;
        }
        Object.assign(policy, updates, { updatedAt: new Date() });
        this.policyVersion++;
        this.lastPolicyUpdate = new Date();
        return true;
    }
    /**
     * Disable/enable a policy
     */
    setPolicyEnabled(policyId, enabled) {
        const policy = this.policies.get(policyId);
        if (!policy) {
            return false;
        }
        policy.enabled = enabled;
        policy.updatedAt = new Date();
        this.policyVersion++;
        return true;
    }
    /**
     * Delete a policy
     */
    deletePolicy(policyId) {
        return this.policies.delete(policyId);
    }
    /**
     * Evaluate access decision based on policies
     */
    evaluateAccess(context) {
        const matchedPolicies = [];
        const deniedPolicies = [];
        let decision = PolicyAction.DENY; // Default deny
        let riskScore = 0;
        const reasons = [];
        // Get enabled policies sorted by priority (highest first)
        const sortedPolicies = Array.from(this.policies.values())
            .filter((p) => p.enabled)
            .sort((a, b) => b.priority - a.priority);
        // Evaluate each policy
        for (const policy of sortedPolicies) {
            // Check if principal matches
            if (!this.matchesPrincipal(context.principal, context.principalType, policy.principal)) {
                continue;
            }
            // Check if action matches
            if (!this.matchesAction(context.action, policy.action)) {
                continue;
            }
            // Check if resource matches
            if (!this.matchesResource(context.resource, policy.resource)) {
                continue;
            }
            // Check additional conditions
            if (policy.condition && !this.evaluateCondition(policy.condition, context.attributes)) {
                continue;
            }
            // Policy matched
            if (policy.effect === 'deny') {
                decision = PolicyAction.DENY;
                deniedPolicies.push(policy.policyId);
                reasons.push(`Denied by policy: ${policy.name}`);
                riskScore += 50;
            }
            else if (policy.effect === 'allow' && decision !== PolicyAction.DENY) {
                decision = PolicyAction.ALLOW;
                matchedPolicies.push(policy.policyId);
                reasons.push(`Allowed by policy: ${policy.name}`);
                riskScore = Math.max(riskScore - 30, 0);
            }
            // Stop at first explicit deny
            if (decision === PolicyAction.DENY) {
                break;
            }
        }
        const policyDecision = {
            decision,
            matchedPolicies,
            deniedPolicies,
            reason: reasons.length > 0 ? reasons[0] : 'No matching policies',
            riskScore
        };
        // Record decision
        this.policyDecisions.push(policyDecision);
        if (this.policyDecisions.length > this.maxDecisionHistorySize) {
            this.policyDecisions = this.policyDecisions.slice(-this.maxDecisionHistorySize);
        }
        return policyDecision;
    }
    /**
     * Check if principal matches policy principal condition
     */
    matchesPrincipal(principal, principalType, condition) {
        if (condition.type === 'any') {
            return true;
        }
        if (condition.type !== principalType) {
            return false;
        }
        if (condition.identifiers.includes('*')) {
            return true;
        }
        return condition.identifiers.includes(principal);
    }
    /**
     * Check if action matches policy action list
     */
    matchesAction(action, policyActions) {
        if (policyActions.includes('*')) {
            return true;
        }
        return policyActions.includes(action);
    }
    /**
     * Check if resource matches policy resource condition
     */
    matchesResource(resource, condition) {
        if (condition.type === 'all') {
            return true;
        }
        if (condition.type === 'specific') {
            return condition.resources.includes(resource);
        }
        if (condition.type === 'pattern') {
            for (const pattern of condition.resources) {
                if (this.matchesPattern(resource, pattern)) {
                    return true;
                }
            }
            return false;
        }
        return false;
    }
    /**
     * Check if resource matches wildcard pattern
     */
    matchesPattern(resource, pattern) {
        if (pattern === '*') {
            return true;
        }
        const regexPattern = pattern
            .replace(/\./g, '\\.')
            .replace(/\*/g, '.*');
        const regex = new RegExp(`^${regexPattern}$`);
        return regex.test(resource);
    }
    /**
     * Evaluate conditional expression
     */
    evaluateCondition(expression, attributes) {
        if (expression.type === 'and') {
            return expression.conditions.every((c) => this.evaluateSingleCondition(c, attributes));
        }
        if (expression.type === 'or') {
            return expression.conditions.some((c) => this.evaluateSingleCondition(c, attributes));
        }
        if (expression.type === 'not') {
            return !expression.conditions.every((c) => this.evaluateSingleCondition(c, attributes));
        }
        return false;
    }
    /**
     * Evaluate single condition
     */
    evaluateSingleCondition(condition, attributes) {
        const value = attributes[condition.attribute];
        switch (condition.operator) {
            case 'equals':
                return value === condition.value;
            case 'not_equals':
                return value !== condition.value;
            case 'greater_than':
                return value > condition.value;
            case 'less_than':
                return value < condition.value;
            case 'contains':
                return typeof value === 'string' && value.includes(condition.value);
            case 'in':
                return Array.isArray(condition.value) && condition.value.includes(value);
            case 'exists':
                return value !== undefined && value !== null;
            default:
                return false;
        }
    }
    /**
     * Get policy statistics
     */
    getPolicyStats() {
        let enabledCount = 0;
        let disabledCount = 0;
        for (const policy of this.policies.values()) {
            if (policy.enabled) {
                enabledCount++;
            }
            else {
                disabledCount++;
            }
        }
        const allowDecisions = this.policyDecisions.filter((d) => d.decision === PolicyAction.ALLOW).length;
        const denyDecisions = this.policyDecisions.filter((d) => d.decision === PolicyAction.DENY).length;
        return {
            totalPolicies: this.policies.size,
            enabledPolicies: enabledCount,
            disabledPolicies: disabledCount,
            totalDecisions: this.policyDecisions.length,
            allowDecisions,
            denyDecisions,
            policyVersion: this.policyVersion,
            lastUpdate: this.lastPolicyUpdate
        };
    }
    /**
     * Get policies by type or filter
     */
    getPolicies(filter) {
        let policies = Array.from(this.policies.values());
        if (filter) {
            if (filter.effect) {
                policies = policies.filter((p) => p.effect === filter.effect);
            }
            if (filter.enabled !== undefined) {
                policies = policies.filter((p) => p.enabled === filter.enabled);
            }
            if (filter.resource) {
                policies = policies.filter((p) => this.matchesResource(filter.resource || '', p.resource));
            }
        }
        return policies.sort((a, b) => b.priority - a.priority);
    }
    /**
     * Audit policy decisions
     */
    getDecisionAudit(limit = 1000) {
        return this.policyDecisions.slice(-limit);
    }
    /**
     * Get permission for user/role/resource combination
     */
    hasPermission(principal, principalType, action, resource) {
        const decision = this.evaluateAccess({
            principal,
            principalType: principalType,
            action,
            resource,
            attributes: {},
            timestamp: new Date()
        });
        return decision.decision === PolicyAction.ALLOW;
    }
}
exports.SecurityPolicyEnforcer = SecurityPolicyEnforcer;
//# sourceMappingURL=SecurityPolicyEnforcer.js.map