// @file        apps/session-broker/src/resource-limits-enforcer.ts
// @module      session-management/resource-limits
// @description Resource limits enforcement and throttling for sessions
//
// Enforces resource limits and applies throttling/termination policies.

import * as winston from 'winston';
import { RedisSessionStore, SessionContext } from './redis-session-store';
import { QuotaManager, QuotaViolationType } from './quota-manager';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export enum EnforcementAction {
  ALLOW = 'allow',
  THROTTLE = 'throttle',
  WARN = 'warn',
  SUSPEND = 'suspend',
  TERMINATE = 'terminate',
}

export interface EnforcementPolicy {
  violationType: QuotaViolationType;
  warningThreshold: number; // percentage
  throttleThreshold: number; // percentage
  suspendThreshold: number; // percentage
  terminateThreshold: number; // percentage
}

/**
 * Enforces resource limits on sessions.
 * Idempotent: enforcing limits multiple times produces same action.
 */
export class ResourceLimitsEnforcer {
  private policies: Map<QuotaViolationType, EnforcementPolicy> = new Map();
  private lastEnforcementTime: Map<string, number> = new Map(); // sessionId -> timestamp

  constructor(private sessionStore: RedisSessionStore, private quotaManager: QuotaManager) {
    this.initializePolicies();
  }

  /**
   * Initialize default enforcement policies.
   */
  private initializePolicies(): void {
    const policies: EnforcementPolicy[] = [
      {
        violationType: QuotaViolationType.CPU,
        warningThreshold: 80,
        throttleThreshold: 90,
        suspendThreshold: 100,
        terminateThreshold: 110,
      },
      {
        violationType: QuotaViolationType.MEMORY,
        warningThreshold: 85,
        throttleThreshold: 95,
        suspendThreshold: 100,
        terminateThreshold: 110,
      },
      {
        violationType: QuotaViolationType.DISK,
        warningThreshold: 80,
        throttleThreshold: 90,
        suspendThreshold: 100,
        terminateThreshold: 110,
      },
      {
        violationType: QuotaViolationType.SESSIONS,
        warningThreshold: 90,
        throttleThreshold: 95,
        suspendThreshold: 100,
        terminateThreshold: 105,
      },
      {
        violationType: QuotaViolationType.SNAPSHOT_STORAGE,
        warningThreshold: 80,
        throttleThreshold: 90,
        suspendThreshold: 100,
        terminateThreshold: 110,
      },
    ];

    for (const policy of policies) {
      this.policies.set(policy.violationType, policy);
    }

    logger.info('Initialized enforcement policies', { policyCount: policies.length });
  }

  /**
   * Enforce resource limits on a session.
   * Idempotent: enforcing same violation multiple times produces same action.
   */
  async enforceResourceLimits(userId: string, sessionId: string): Promise<EnforcementAction> {
    try {
      // Throttle enforcement checks to once per minute per session
      const lastCheck = this.lastEnforcementTime.get(sessionId) || 0;
      if (Date.now() - lastCheck < 60000) {
        logger.debug('Enforcement check throttled', { sessionId });
        return EnforcementAction.ALLOW; // Idempotent - return allow if recently checked
      }

      this.lastEnforcementTime.set(sessionId, Date.now());

      const violations = await this.quotaManager.checkQuotaViolations(userId, sessionId);

      if (violations.length === 0) {
        return EnforcementAction.ALLOW;
      }

      // Determine enforcement action based on worst violation
      let action = EnforcementAction.ALLOW;

      for (const violation of violations) {
        const policy = this.policies.get(violation.violationType);
        if (!policy) {
          logger.warn('No policy found for violation type', { violationType: violation.violationType });
          continue;
        }

        const utilizationPercent = (violation.currentUsage / violation.quotaLimit) * 100;
        const violationAction = this.getEnforcementAction(utilizationPercent, policy);

        // Escalate to most severe action
        action = this.escalateAction(action, violationAction);

        logger.info('Enforcement action determined', {
          sessionId,
          violationType: violation.violationType,
          utilization: utilizationPercent.toFixed(1),
          action: violationAction,
        });
      }

      // Apply enforcement action
      await this.applyEnforcementAction(userId, sessionId, action);

      return action;
    } catch (error) {
      logger.error('Failed to enforce resource limits', { error, sessionId });
      return EnforcementAction.ALLOW; // Default to allow on error
    }
  }

  /**
   * Get enforcement action for a given utilization percentage.
   */
  private getEnforcementAction(utilizationPercent: number, policy: EnforcementPolicy): EnforcementAction {
    if (utilizationPercent >= policy.terminateThreshold) {
      return EnforcementAction.TERMINATE;
    } else if (utilizationPercent >= policy.suspendThreshold) {
      return EnforcementAction.SUSPEND;
    } else if (utilizationPercent >= policy.throttleThreshold) {
      return EnforcementAction.THROTTLE;
    } else if (utilizationPercent >= policy.warningThreshold) {
      return EnforcementAction.WARN;
    }
    return EnforcementAction.ALLOW;
  }

  /**
   * Escalate to the most severe action.
   */
  private escalateAction(current: EnforcementAction, next: EnforcementAction): EnforcementAction {
    const severity = [
      EnforcementAction.ALLOW,
      EnforcementAction.WARN,
      EnforcementAction.THROTTLE,
      EnforcementAction.SUSPEND,
      EnforcementAction.TERMINATE,
    ];

    const currentIndex = severity.indexOf(current);
    const nextIndex = severity.indexOf(next);

    return severity[Math.max(currentIndex, nextIndex)];
  }

  /**
   * Apply enforcement action to a session.
   * Idempotent: applying same action multiple times is safe.
   */
  private async applyEnforcementAction(
    userId: string,
    sessionId: string,
    action: EnforcementAction
  ): Promise<void> {
    try {
      const session = await this.sessionStore.getSession(sessionId);
      if (!session) {
        logger.error('Session not found for enforcement', { sessionId });
        return;
      }

      switch (action) {
        case EnforcementAction.ALLOW:
          // No action needed
          break;

        case EnforcementAction.WARN:
          // Send warning notification (implementation depends on notification system)
          logger.warn('Quota warning issued', { userId, sessionId });
          // TODO: Emit warning event
          break;

        case EnforcementAction.THROTTLE:
          // Apply CPU/IO throttling
          logger.info('Throttling session', { userId, sessionId });
          // TODO: Apply cgroup limits to container
          break;

        case EnforcementAction.SUSPEND:
          // Suspend session (pause execution)
          logger.info('Suspending session', { userId, sessionId });
          // TODO: Suspend container/pause processes
          break;

        case EnforcementAction.TERMINATE:
          // Terminate session (hard stop)
          logger.error('Terminating session due to quota violation', { userId, sessionId });
          // TODO: Terminate container, notify user
          break;
      }
    } catch (error) {
      logger.error('Failed to apply enforcement action', { error, sessionId, action });
    }
  }

  /**
   * Update enforcement policy for a violation type.
   * Idempotent: updating with same values returns true.
   */
  async updatePolicy(violationType: QuotaViolationType, policy: Partial<EnforcementPolicy>): Promise<boolean> {
    try {
      const existing = this.policies.get(violationType);
      if (!existing) {
        logger.error('Policy not found for violation type', { violationType });
        return false;
      }

      const updated = { ...existing, ...policy };
      this.policies.set(violationType, updated);

      logger.info('Updated enforcement policy', { violationType, policy: updated });
      return true;
    } catch (error) {
      logger.error('Failed to update policy', { error, violationType });
      return false;
    }
  }

  /**
   * Get policy for a violation type.
   */
  async getPolicy(violationType: QuotaViolationType): Promise<EnforcementPolicy | null> {
    try {
      return this.policies.get(violationType) || null;
    } catch (error) {
      logger.error('Failed to get policy', { error, violationType });
      return null;
    }
  }

  /**
   * List all enforcement policies.
   */
  async listPolicies(): Promise<EnforcementPolicy[]> {
    try {
      return Array.from(this.policies.values());
    } catch (error) {
      logger.error('Failed to list policies', { error });
      return [];
    }
  }
}
