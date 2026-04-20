import type { SessionLifecycleState } from './session-policy.js';

export type SessionBrokerRole = 'requester' | 'operator' | 'approver' | 'admin' | 'auditor' | 'break-glass';

export type SessionBrokerAction =
  | 'launch'
  | 'approve'
  | 'terminate'
  | 'break-glass-terminate'
  | 'view'
  | 'audit'
  | 'publish';

export interface SessionBrokerPrincipal {
  userId: string;
  username: string;
  email: string;
  groups: string[];
  roles: SessionBrokerRole[];
}

export interface SessionBrokerAccessConfig {
  adminGroups: string[];
  operatorGroups: string[];
  approverGroups: string[];
  auditorGroups: string[];
  breakGlassGroups: string[];
}

export interface SessionBrokerAccessContext {
  sessionId?: string;
  ownerUserId?: string;
  approvalRequired?: boolean;
  sessionStatus?: SessionLifecycleState;
  reasonCode?: string;
}

export interface SessionBrokerAccessDecision {
  allowed: boolean;
  statusCode: number;
  policyCode: string;
  reason: string;
  requiredRoles?: SessionBrokerRole[];
  reasonCodeRequired?: boolean;
}

export interface SessionBrokerPolicyMatrix {
  requester: {
    launchOwn: boolean;
    viewOwn: boolean;
    terminateOwn: boolean;
    approve: boolean;
    breakGlass: boolean;
  };
  operator: {
    launchOwn: boolean;
    launchForOthers: boolean;
    viewAny: boolean;
    terminateAny: boolean;
    approve: boolean;
    breakGlass: boolean;
  };
  approver: {
    approve: boolean;
    viewEvidence: boolean;
  };
  admin: {
    all: boolean;
  };
  auditor: {
    viewEvidence: boolean;
    readOnly: boolean;
  };
  breakGlass: {
    terminateAny: boolean;
    reasonRequired: boolean;
  };
}

export const DEFAULT_SESSION_BROKER_CONFIG: SessionBrokerAccessConfig = {
  adminGroups: ['admin'],
  operatorGroups: ['operator', 'sre', 'oncall'],
  approverGroups: ['approver', 'operator', 'admin'],
  auditorGroups: ['auditor', 'security-auditor'],
  breakGlassGroups: ['break-glass', 'breakglass', 'emergency', 'admin'],
};

const normalizeTokens = (values: string[]): string[] => {
  const normalized = new Set<string>();

  for (const value of values) {
    const token = value.trim().toLowerCase();
    if (token) {
      normalized.add(token);
    }
  }

  return [...normalized];
};

export const parseDelimitedValues = (value: string | string[] | undefined): string[] => {
  if (!value) {
    return [];
  }

  const raw = Array.isArray(value) ? value.join(',') : value;
  return normalizeTokens(
    raw
      .split(/[,;\s]+/)
      .map((entry) => entry.trim())
      .filter(Boolean),
  );
};

export const deriveSessionBrokerRoles = (
  groups: string[],
  config: SessionBrokerAccessConfig = DEFAULT_SESSION_BROKER_CONFIG,
): SessionBrokerRole[] => {
  const normalizedGroups = new Set(normalizeTokens(groups));
  const roles = new Set<SessionBrokerRole>(['requester']);

  const addRoleIfMatched = (role: SessionBrokerRole, allowedGroups: string[]): void => {
    if (allowedGroups.some((group) => normalizedGroups.has(group))) {
      roles.add(role);
    }
  };

  addRoleIfMatched('admin', config.adminGroups);
  addRoleIfMatched('operator', config.operatorGroups);
  addRoleIfMatched('approver', config.approverGroups);
  addRoleIfMatched('auditor', config.auditorGroups);
  addRoleIfMatched('break-glass', config.breakGlassGroups);

  if (roles.has('admin')) {
    roles.add('operator');
    roles.add('approver');
    roles.add('auditor');
    roles.add('break-glass');
  }

  return [...roles];
};

export const buildSessionBrokerPrincipal = (
  input: {
    userId: string;
    username: string;
    email: string;
    groups?: string[] | string;
  },
  config: SessionBrokerAccessConfig = DEFAULT_SESSION_BROKER_CONFIG,
): SessionBrokerPrincipal => {
  const groups = parseDelimitedValues(input.groups);

  return {
    userId: input.userId,
    username: input.username,
    email: input.email,
    groups,
    roles: deriveSessionBrokerRoles(groups, config),
  };
};

export const hasBrokerRole = (principal: SessionBrokerPrincipal, roles: SessionBrokerRole[]): boolean => {
  const roleSet = new Set(principal.roles);
  return roles.some((role) => roleSet.has(role));
};

export const isSessionApprovalPending = (
  sessionStatus: SessionLifecycleState,
  approvalRequired: boolean,
): boolean => approvalRequired && sessionStatus === 'testing';

export const buildSessionBrokerPolicyMatrix = (): SessionBrokerPolicyMatrix => ({
  requester: {
    launchOwn: true,
    viewOwn: true,
    terminateOwn: true,
    approve: false,
    breakGlass: false,
  },
  operator: {
    launchOwn: true,
    launchForOthers: true,
    viewAny: true,
    terminateAny: true,
    approve: true,
    breakGlass: true,
  },
  approver: {
    approve: true,
    viewEvidence: true,
  },
  admin: {
    all: true,
  },
  auditor: {
    viewEvidence: true,
    readOnly: true,
  },
  breakGlass: {
    terminateAny: true,
    reasonRequired: true,
  },
});

const principalHasElevatedRole = (principal: SessionBrokerPrincipal): boolean =>
  hasBrokerRole(principal, ['admin', 'operator', 'approver', 'break-glass']);

const principalCanReadEvidence = (principal: SessionBrokerPrincipal, ownerUserId?: string): boolean =>
  principal.userId === ownerUserId || hasBrokerRole(principal, ['admin', 'operator', 'approver', 'auditor']);

export const authorizeSessionLaunch = (
  principal: SessionBrokerPrincipal,
  requestedUserId: string,
): SessionBrokerAccessDecision => {
  if (requestedUserId !== principal.userId && !hasBrokerRole(principal, ['operator', 'admin'])) {
    return {
      allowed: false,
      statusCode: 403,
      policyCode: 'launch_forbidden',
      reason: 'Only operator or admin principals may launch sessions for other users',
    };
  }

  return {
    allowed: true,
    statusCode: 200,
    policyCode: 'launch_allowed',
    reason: 'Session launch authorized',
  };
};

export const authorizeSessionApproval = (
  principal: SessionBrokerPrincipal,
): SessionBrokerAccessDecision => {
  if (!hasBrokerRole(principal, ['approver', 'operator', 'admin'])) {
    return {
      allowed: false,
      statusCode: 403,
      policyCode: 'approval_forbidden',
      reason: 'Approval requires approver, operator, or admin role',
      requiredRoles: ['approver', 'operator', 'admin'],
    };
  }

  return {
    allowed: true,
    statusCode: 200,
    policyCode: 'approval_allowed',
    reason: 'Approval authorized',
  };
};

export const authorizeSessionView = (
  principal: SessionBrokerPrincipal,
  ownerUserId?: string,
): SessionBrokerAccessDecision => {
  if (principalCanReadEvidence(principal, ownerUserId)) {
    return {
      allowed: true,
      statusCode: 200,
      policyCode: 'view_allowed',
      reason: 'Session evidence is visible to the principal',
    };
  }

  return {
    allowed: false,
    statusCode: 403,
    policyCode: 'view_forbidden',
    reason: 'Session evidence is restricted to the owner, operator, approver, auditor, or admin',
    requiredRoles: ['operator', 'approver', 'admin', 'auditor'],
  };
};

export const authorizeSessionTermination = (
  principal: SessionBrokerPrincipal,
  ownerUserId?: string,
): SessionBrokerAccessDecision => {
  if (principal.userId === ownerUserId || principalHasElevatedRole(principal)) {
    return {
      allowed: true,
      statusCode: 200,
      policyCode: 'termination_allowed',
      reason: 'Session termination authorized',
    };
  }

  return {
    allowed: false,
    statusCode: 403,
    policyCode: 'termination_forbidden',
    reason: 'Session termination requires ownership or an elevated role',
    requiredRoles: ['operator', 'approver', 'admin', 'break-glass'],
  };
};

export const authorizeBreakGlassTermination = (
  principal: SessionBrokerPrincipal,
  ownerUserId?: string,
  reasonCode?: string,
): SessionBrokerAccessDecision => {
  if (!hasBrokerRole(principal, ['operator', 'admin', 'break-glass'])) {
    return {
      allowed: false,
      statusCode: 403,
      policyCode: 'break_glass_forbidden',
      reason: 'Break-glass termination requires operator, admin, or break-glass role',
      requiredRoles: ['operator', 'admin', 'break-glass'],
    };
  }

  if (!reasonCode || reasonCode.trim() === '') {
    return {
      allowed: false,
      statusCode: 422,
      policyCode: 'break_glass_reason_required',
      reason: 'Break-glass termination requires a reason code',
      reasonCodeRequired: true,
    };
  }

  if (principal.userId === ownerUserId) {
    return {
      allowed: false,
      statusCode: 409,
      policyCode: 'break_glass_owner_conflict',
      reason: 'Break-glass termination is reserved for another principal or an elevated operator',
    };
  }

  return {
    allowed: true,
    statusCode: 200,
    policyCode: 'break_glass_allowed',
    reason: 'Break-glass termination authorized',
  };
};

export const evaluateSessionPublication = (
  sessionStatus: SessionLifecycleState,
  approvalRequired: boolean,
): SessionBrokerAccessDecision => {
  if (isSessionApprovalPending(sessionStatus, approvalRequired)) {
    return {
      allowed: false,
      statusCode: 423,
      policyCode: 'approval_pending',
      reason: 'Session approval is required before the live URL can be published',
    };
  }

  if (sessionStatus !== 'ready') {
    return {
      allowed: false,
      statusCode: 409,
      policyCode: 'session_not_ready',
      reason: `Session must be ready before the live URL can be published (current state: ${sessionStatus})`,
    };
  }

  return {
    allowed: true,
    statusCode: 200,
    policyCode: 'publish_allowed',
    reason: 'Live URL publication authorized',
  };
};
