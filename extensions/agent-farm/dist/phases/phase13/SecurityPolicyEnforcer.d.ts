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
export declare enum PolicyAction {
    ALLOW = "allow",
    DENY = "deny",
    CHALLENGE = "challenge"
}
export interface AccessPolicy {
    policyId: string;
    name: string;
    description: string;
    effect: 'allow' | 'deny';
    principal: PrincipalCondition;
    action: string[];
    resource: ResourceCondition;
    condition?: ConditionalExpression;
    priority: number;
    enabled: boolean;
    createdAt: Date;
    updatedAt: Date;
    createdBy: string;
}
export interface PrincipalCondition {
    type: 'user' | 'group' | 'role' | 'service' | 'any';
    identifiers: string[];
    attributes?: Record<string, string>;
}
export interface ResourceCondition {
    type: 'all' | 'specific' | 'pattern';
    resources: string[];
    attributes?: Record<string, string>;
}
export interface ConditionalExpression {
    type: 'and' | 'or' | 'not';
    conditions: Condition[];
}
export interface Condition {
    attribute: string;
    operator: 'equals' | 'not_equals' | 'greater_than' | 'less_than' | 'contains' | 'in' | 'exists';
    value: any;
}
export interface PolicyEvaluationContext {
    principal: string;
    principalType: 'user' | 'group' | 'role' | 'service';
    action: string;
    resource: string;
    attributes: Record<string, any>;
    timestamp: Date;
    ipAddress?: string;
    userAgent?: string;
}
export interface PolicyDecision {
    decision: PolicyAction;
    matchedPolicies: string[];
    deniedPolicies: string[];
    reason: string;
    riskScore: number;
}
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
export declare class SecurityPolicyEnforcer {
    private policies;
    private policyDecisions;
    private readonly maxDecisionHistorySize;
    private policyVersion;
    private lastPolicyUpdate;
    constructor();
    /**
     * Register default security policies
     */
    private registerDefaultPolicies;
    /**
     * Add a new policy
     */
    addPolicy(policy: AccessPolicy): void;
    /**
     * Update an existing policy
     */
    updatePolicy(policyId: string, updates: Partial<AccessPolicy>): boolean;
    /**
     * Disable/enable a policy
     */
    setPolicyEnabled(policyId: string, enabled: boolean): boolean;
    /**
     * Delete a policy
     */
    deletePolicy(policyId: string): boolean;
    /**
     * Evaluate access decision based on policies
     */
    evaluateAccess(context: PolicyEvaluationContext): PolicyDecision;
    /**
     * Check if principal matches policy principal condition
     */
    private matchesPrincipal;
    /**
     * Check if action matches policy action list
     */
    private matchesAction;
    /**
     * Check if resource matches policy resource condition
     */
    private matchesResource;
    /**
     * Check if resource matches wildcard pattern
     */
    private matchesPattern;
    /**
     * Evaluate conditional expression
     */
    private evaluateCondition;
    /**
     * Evaluate single condition
     */
    private evaluateSingleCondition;
    /**
     * Get policy statistics
     */
    getPolicyStats(): {
        totalPolicies: number;
        enabledPolicies: number;
        disabledPolicies: number;
        totalDecisions: number;
        allowDecisions: number;
        denyDecisions: number;
        policyVersion: number;
        lastUpdate: Date;
    };
    /**
     * Get policies by type or filter
     */
    getPolicies(filter?: {
        effect?: 'allow' | 'deny';
        enabled?: boolean;
        resource?: string;
    }): AccessPolicy[];
    /**
     * Audit policy decisions
     */
    getDecisionAudit(limit?: number): PolicyDecision[];
    /**
     * Get permission for user/role/resource combination
     */
    hasPermission(principal: string, principalType: string, action: string, resource: string): boolean;
}
//# sourceMappingURL=SecurityPolicyEnforcer.d.ts.map
