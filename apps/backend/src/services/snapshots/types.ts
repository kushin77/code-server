/**
 * Session Snapshots Service Types
 * Full-fidelity snapshots with history and fast restore (<10s)
 */

/**
 * File state at snapshot time
 */
export interface FileState {
  path: string;
  content: string;
  encoding: string;
  isModified: boolean;
  isUnsaved: boolean;
  lastModified: number;
}

/**
 * Editor layout configuration
 */
export interface EditorLayout {
  groups: {
    id: string;
    size: number;
    editors: {
      id: string;
      path?: string;
      isActive: boolean;
      position: number;
    }[];
  }[];
  focusedGroupId?: string;
  focusedEditorId?: string;
}

/**
 * Terminal state
 */
export interface TerminalState {
  id: string;
  name: string;
  shellPath: string;
  shellArgs: string[];
  cwd: string;
  history: string[];
  isActive: boolean;
  lines: number;
}

/**
 * Debug configuration
 */
export interface DebugState {
  isDebugging: boolean;
  configuration: {
    name: string;
    type: string;
    request: 'launch' | 'attach';
    program?: string;
    args?: string[];
    cwd?: string;
  };
  breakpoints: {
    path: string;
    line: number;
    column?: number;
    condition?: string;
    logMessage?: string;
  }[];
  callStack?: {
    frame: number;
    file: string;
    line: number;
    function: string;
  }[];
  variables?: Record<string, unknown>;
  isPaused: boolean;
}

/**
 * Extension state
 */
export interface ExtensionState {
  id: string;
  name: string;
  version: string;
  enabled: boolean;
  path?: string;
  settings?: Record<string, unknown>;
}

/**
 * Workspace settings snapshot
 */
export interface WorkspaceSettings {
  theme: string;
  fontSize: number;
  fontFamily: string;
  formatOnSave: boolean;
  tabSize: number;
  wordWrap: boolean;
  extensions: ExtensionState[];
  keybindings?: Record<string, string>;
  custom?: Record<string, unknown>;
}

/**
 * Full session snapshot
 */
export interface SessionSnapshot {
  id: string;
  userId: string;
  userEmail: string;
  workspaceId: string;
  sessionId: string;
  timestamp: number;
  version: number; // 1-10 for history
  duration: number; // ms since session start
  files: FileState[];
  layout: EditorLayout;
  terminals: TerminalState[];
  debug?: DebugState;
  settings: WorkspaceSettings;
  metadata: {
    osType: string;
    vscodeVersion: string;
    workspacePath: string;
    totalFileSize: number; // bytes
    fileCount: number;
  };
  tags?: string[]; // Manual tags for snapshots
  description?: string;
}

/**
 * Snapshot summary (lightweight reference)
 */
export interface SnapshotSummary {
  id: string;
  version: number;
  timestamp: number;
  duration: number;
  fileCount: number;
  terminalCount: number;
  totalSize: number; // bytes
  tags?: string[];
  description?: string;
}

/**
 * Snapshot restore request
 */
export interface RestoreRequest {
  userId: string;
  userEmail: string;
  snapshotId: string;
  restoreOptions: {
    restoreFiles: boolean;
    restoreLayout: boolean;
    restoreTerminals: boolean;
    restoreDebug: boolean;
    restoreSettings: boolean;
    restoreExtensions: boolean;
  };
}

/**
 * Snapshot restore result
 */
export interface RestoreResult {
  snapshotId: string;
  successful: boolean;
  startTime: number;
  endTime: number;
  duration: number; // ms
  filesRestored: number;
  errors?: {
    file: string;
    reason: string;
  }[];
}

/**
 * SOC2 audit entry for snapshots
 */
export interface SnapshotAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'created' | 'restored' | 'deleted' | 'tagged' | 'exported' | 'imported';
  status: 'success' | 'denied' | 'error';
  snapshotId: string;
  snapshotVersion?: number;
  ipAddress?: string;
  userAgent?: string;
  timestamp: number;
  duration?: number; // For restore operations
  fileCount?: number;
  details?: Record<string, unknown>;
}

/**
 * Snapshot metadata
 */
export interface SnapshotMetadata {
  snapshotId: string;
  userId: string;
  userEmail: string;
  workspaceId: string;
  version: number;
  createdAt: number;
  createdBy: string;
  size: number; // bytes
  fileCount: number;
  terminalCount: number;
  debugConfig?: string;
  tags: string[];
  description?: string;
  isAutomatic: boolean; // True if auto-created on interval
  ttl?: number; // Time-to-live in ms, undefined = permanent
}

/**
 * Snapshot statistics
 */
export interface SnapshotStatistics {
  totalSnapshots: number;
  snapshotsByVersion: Record<number, number>;
  snapshotsByUser: Record<string, number>;
  snapshotsByWorkspace: Record<string, number>;
  totalStorageBytes: number;
  averageSnapshotSize: number;
  averageRestoreTime: number;
  restoreSuccessRate: number;
  autoSnapshots: number;
  manualSnapshots: number;
  oldestSnapshot: number;
  newestSnapshot: number;
}

/**
 * Snapshot query
 */
export interface SnapshotQuery {
  userId?: string;
  workspaceId?: string;
  version?: number;
  tags?: string[];
  fromTime?: number;
  toTime?: number;
  limit?: number;
  offset?: number;
}

/**
 * Snapshot query result
 */
export interface SnapshotQueryResult {
  snapshots: SnapshotSummary[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * Snapshot storage configuration
 */
export interface SnapshotStorageConfig {
  enabled: boolean;
  maxVersions: number; // Default 10
  maxSnapshotsPerUser: number; // Default 100
  maxStorageBytes: number; // Default 10GB per user
  autoSnapshotInterval: number; // ms (0 = disabled)
  compressionEnabled: boolean;
  encryptionEnabled: boolean;
  retentionDays: number; // Auto-delete after N days (0 = unlimited)
  backupEnabled: boolean;
}

/**
 * Snapshot comparison result
 */
export interface SnapshotComparison {
  fromVersion: number;
  toVersion: number;
  filesAdded: string[];
  filesDeleted: string[];
  filesModified: {
    path: string;
    insertions: number;
    deletions: number;
  }[];
  layoutChanged: boolean;
  debugConfigChanged: boolean;
  extensionsAdded: ExtensionState[];
  extensionsRemoved: ExtensionState[];
}

/**
 * Snapshot export format
 */
export interface SnapshotExport {
  format: 'zip' | 'tar' | 'json';
  snapshotId: string;
  version: number;
  timestamp: number;
  compressed: boolean;
  encryptionKey?: string;
}

/**
 * Snapshot service configuration
 */
export interface SnapshotServiceConfig {
  enabled: boolean;
  auditLoggingEnabled: boolean;
  maxVersions: number;
  maxSnapshotsPerUser: number;
  autoSnapshotEnabled: boolean;
  autoSnapshotInterval: number;
  restoreTimeoutMs: number;
  compressionEnabled: boolean;
  encryptionEnabled: boolean;
  maxAuditLogSize: number;
  storageBackend: 'memory' | 'disk' | 's3';
}
