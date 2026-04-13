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

export enum PolicyAction {
  ALLOW = 'allow',
  DENY = 'deny',
  CHALLENGE = 'challenge'
}

export interface AccessPolicy {
  policyId: string;
  name: string;
  description: string;
  effect: 'allow' | 'deny';
  principal: PrincipalCondition;
  action: string[];  // Actions: read, write, delete, execute, escalate, etc.
  resource: ResourceCondition;
  condition?: ConditionalExpression;
  priority: number;  // Higher priority evaluated first
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
export class SecurityPolicyEnforcer {
  private policies: Map<string, AccessPolicy> = new Map();
  private policyDecisions: PolicyDecision[] = [];
  private readonly maxDecisionHistorySize = 100000;
  private policyVersion = 0;
  private lastPolicyUpdate = new Date();

  constructor() {
    this.registerDefaultPolicies();
  }

  /**
   * Register default security policies
   */
  private registerDefaultPolicies(): void {
    // Policy 1: Deny all by default (zero-trust)
    this.addPolicy({
      policyId: 'policy_default_deny',
      name: 'Default Deny All',
      description: 'Deny all access unless explicitly allowed',
      effect: 'deny',
      principal: { type: 'any', identifiers: ['*'] },
      action: ['*'],
      resource: { type: 'all', resources: ['*'] },
      priority: 0,  // Lowest priority
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
      priority: 100,  // High priority
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
          { attribute: 'dataSize', operator: 'greater_than', value: 100 * 1024 * 1024 }  // > 100 MB
        ]
      },
      priority: 95,  // Very high priority
      enabled: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: 'system'
    });
  }

  /**
   * Add a new policy
   */
  addPolicy(policy: AccessPolicy): void {
    this.policies.set(policy.policyId, policy);
    this.policyVersion++;
    this.lastPolicyUpdate = new Date();
  }

  /**
   * Update an existing policy
   */
  updatePolicy(policyId: string, updates: Partial<AccessPolicy>): boolean {
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
  setPolicyEnabled(policyId: string, enabled: boolean): boolean {
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
  deletePolicy(policyId: string): boolean {
    return this.policies.delete(policyId);
  }

  /**
   * Evaluate access decision based on policies
   */
  evaluateAccess(context: PolicyEvaluationContext): PolicyDecision {
    const matchedPolicies: string[] = [];
    const deniedPolicies: string[] = [];
    let decision = PolicyAction.DENY;  // Default deny
    let riskScore = 0;
    const reasons: string[] = [];

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
      } else if (policy.effect === 'allow' && decision !== PolicyAction.DENY) {
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

    const policyDecision: PolicyDecision = {
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
  private matchesPrincipal(principal: string, principalType: string, condition: PrincipalCondition): boolean {
    if (condition.type === 'any') {
      return true;
    }

    if (condition.type !== (principalType as any)) {
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
  private matchesAction(action: string, policyActions: string[]): boolean {
    if (policyActions.includes('*')) {
      return true;
    }

    return policyActions.includes(action);
  }

  /**
   * Check if resource matches policy resource condition
   */
  private matchesResource(resource: string, condition: ResourceCondition): boolean {
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
  private matchesPattern(resource: string, pattern: string): boolean {
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
  private evaluateCondition(expression: ConditionalExpression, attributes: Record<string, any>): boolean {
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
  private evaluateSingleCondition(condition: Condition, attributes: Record<string, any>): boolean {
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
        return typeof value === 'string' && value.includes(condition.value as string);
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
  getPolicyStats(): {
    totalPolicies: number;
    enabledPolicies: number;
    disabledPolicies: number;
    totalDecisions: number;
    allowDecisions: number;
    denyDecisions: number;
    policyVersion: number;
    lastUpdate: Date;
  } {
    let enabledCount = 0;
    let disabledCount = 0;

    for (const policy of this.policies.values()) {
      if (policy.enabled) {
        enabledCount++;
      } else {
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
  getPolicies(filter?: { effect?: 'allow' | 'deny'; enabled?: boolean; resource?: string }): AccessPolicy[] {
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
  getDecisionAudit(limit: number = 1000): PolicyDecision[] {
    return this.policyDecisions.slice(-limit);
  }

  /**
   * Get permission for user/role/resource combination
   */
  hasPermission(principal: string, principalType: string, action: string, resource: string): boolean {
    const decision = this.evaluateAccess({
      principal,
      principalType: principalType as 'user' | 'group' | 'role' | 'service',
      action,
      resource,
      attributes: {},
      timestamp: new Date()
    });

    return decision.decision === PolicyAction.ALLOW;
  }
}
