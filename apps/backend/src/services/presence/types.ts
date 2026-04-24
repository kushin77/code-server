/**
 * Rich Presence System Types
 * Real-time user presence with Redis persistence and SOC2 audit logging
 */

/**
 * Presence status type
 */
export type PresenceStatus = 'online' | 'idle' | 'away' | 'offline' | 'busy';

/**
 * Presence activity context
 */
export type ActivityContext = 'file' | 'function' | 'task' | 'debug' | 'terminal' | 'chat' | 'custom';

/**
 * User presence information
 */
export interface UserPresence {
  userId: string;
  userEmail: string;
  userName?: string;
  status: PresenceStatus;
  lastActivity: number;
  idleSince?: number;
  currentActivity?: {
    context: ActivityContext;
    description: string;
    details?: Record<string, unknown>;
  };
  currentFile?: {
    path: string;
    lineNumber?: number;
    columnNumber?: number;
  };
  currentFunction?: {
    name: string;
    filePath: string;
    lineNumber?: number;
  };
  currentTask?: {
    id: string;
    title: string;
    status: string;
  };
  debugState?: {
    isDebugging: boolean;
    breakpointCount?: number;
    paused?: boolean;
  };
  customStatus?: {
    emoji?: string;
    text: string;
    expiresAt?: number;
  };
  workspaceId?: string;
  sessionId?: string;
  deviceInfo?: {
    platform: string;
    browser?: string;
    ipAddress?: string;
  };
  createdAt: number;
  updatedAt: number;
  expiresAt: number; // TTL for Redis (default 4 hours)
}

/**
 * Presence update
 */
export interface PresenceUpdate {
  userId: string;
  status?: PresenceStatus;
  currentActivity?: UserPresence['currentActivity'];
  currentFile?: UserPresence['currentFile'];
  currentFunction?: UserPresence['currentFunction'];
  currentTask?: UserPresence['currentTask'];
  debugState?: UserPresence['debugState'];
  customStatus?: UserPresence['customStatus'];
}

/**
 * Presence event
 */
export interface PresenceEvent {
  userId: string;
  eventType: 'online' | 'idle' | 'away' | 'offline' | 'activity-changed' | 'status-changed';
  previousStatus?: PresenceStatus;
  newStatus?: PresenceStatus;
  activity?: UserPresence['currentActivity'];
  timestamp: number;
  duration?: number; // For idle/away duration
}

/**
 * SOC2 audit entry for presence operations
 */
export interface PresenceAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'online' | 'offline' | 'idle' | 'away' | 'status-updated' | 'activity-changed' | 'presence-queried';
  status: 'success' | 'denied' | 'error';
  resourceType: 'user-presence' | 'workspace-presence';
  resourceId: string;
  ipAddress?: string;
  userAgent?: string;
  timestamp: number;
  details?: Record<string, unknown>;
  previousStatus?: PresenceStatus;
  newStatus?: PresenceStatus;
}

/**
 * Workspace presence snapshot
 */
export interface WorkspacePresenceSnapshot {
  workspaceId: string;
  activeUsers: number;
  totalUsers: number;
  presenceByStatus: Record<PresenceStatus, number>;
  presenceByActivity: Record<ActivityContext, number>;
  timestamp: number;
  users: UserPresence[];
}

/**
 * Presence statistics
 */
export interface PresenceStatistics {
  totalUsers: number;
  usersByStatus: Record<PresenceStatus, number>;
  usersByActivity: Record<ActivityContext, number>;
  averageSessionDuration: number;
  averageIdleTime: number;
  workspaces: number;
  usersPerWorkspace: Record<string, number>;
  mostActiveTime: number; // Hour of day
  peakConcurrency: number;
}

/**
 * Presence query
 */
export interface PresenceQuery {
  workspaceId?: string;
  userId?: string;
  status?: PresenceStatus;
  activity?: ActivityContext;
  limit?: number;
  offset?: number;
}

/**
 * Presence query result
 */
export interface PresenceQueryResult {
  presence: UserPresence[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * Presence notification
 */
export interface PresenceNotification {
  id: string;
  userId: string;
  type: 'user-online' | 'user-offline' | 'user-idle' | 'activity-changed' | 'colleague-online';
  triggeredBy: string;
  triggeredByEmail: string;
  message: string;
  data: Record<string, unknown>;
  readAt?: number;
  createdAt: number;
}

/**
 * Presence settings
 */
export interface PresenceSettings {
  userId: string;
  showPresence: boolean;
  broadcastActivity: boolean;
  broadcastStatus: boolean;
  broadcastFile: boolean;
  broadcastFunction: boolean;
  broadcastTask: boolean;
  broadcastCustomStatus: boolean;
  privacyLevel: 'public' | 'internal' | 'workspace' | 'private';
  notifyOnCollaboratorOnline: boolean;
  notifyOnCollaboratorOffline: boolean;
  notifyOnActivityChange: boolean;
  idleThreshold: number; // ms before marking idle
  awayThreshold: number; // ms before marking away
  createdAt: number;
  updatedAt: number;
}

/**
 * Presence service configuration
 */
export interface PresenceServiceConfig {
  enabled: boolean;
  auditLoggingEnabled: boolean;
  redisPersistenceEnabled: boolean;
  ttl: number; // Time-to-live in ms (default 4 hours)
  idleThreshold: number; // ms before marking idle (default 15 min)
  awayThreshold: number; // ms before marking away (default 30 min)
  cleanupInterval: number; // How often to clean up expired entries (default 5 min)
  maxPresencePerWorkspace: number;
  enableNotifications: boolean;
  maxAuditLogSize: number;
}

/**
 * Presence history entry
 */
export interface PresenceHistoryEntry {
  userId: string;
  status: PresenceStatus;
  activity?: UserPresence['currentActivity'];
  timestamp: number;
  duration?: number;
}

/**
 * User activity summary
 */
export interface ActivitySummary {
  userId: string;
  date: string;
  onlineTime: number; // ms
  idleTime: number;
  awayTime: number;
  sessionCount: number;
  averageSessionDuration: number;
  mostUsedActivity: ActivityContext;
  filesEdited: number;
  functionsEdited: number;
  tasksCompleted: number;
}
