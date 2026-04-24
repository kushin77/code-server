/**
 * Hot Workspace Switching Service Types
 * Sub-200ms workspace context switching with IndexedDB state persistence
 */

/**
 * Workspace context snapshot
 */
export interface WorkspaceContext {
  workspaceId: string;
  userId: string;
  openFiles: string[]; // File paths
  activeFile: string | null;
  cursorPositions: Map<string, { line: number; character: number }>;
  expandedFolders: string[];
  selectedTerminal: string | null;
  scrollPositions: Map<string, number>;
  editorState: {
    theme: string;
    fontSize: number;
    fontFamily: string;
    wordWrap: boolean;
    minimap: boolean;
  };
  terminalState: {
    shells: Array<{
      id: string;
      cwd: string;
      history: string[];
    }>;
  };
  metadata: {
    lastAccessed: number;
    accessCount: number;
    totalTimeMs: number;
  };
}

/**
 * Workspace switch request
 */
export interface WorkspaceSwitchRequest {
  fromWorkspaceId: string;
  toWorkspaceId: string;
  userId: string;
  timestamp: number;
}

/**
 * Workspace switch result
 */
export interface WorkspaceSwitchResult {
  success: boolean;
  fromWorkspaceId: string;
  toWorkspaceId: string;
  switchTimeMs: number;
  stateRestored: boolean;
  cachedState: boolean; // true if from IndexedDB
  reason?: string;
}

/**
 * Workspace cache entry
 */
export interface WorkspaceCacheEntry {
  context: WorkspaceContext;
  cachedAt: number;
  accessedAt: number;
  size: number; // bytes
  ttlMs: number;
}

/**
 * Hot switch statistics
 */
export interface SwitchStatistics {
  workspaceId: string;
  userId: string;
  totalSwitches: number;
  averageSwitchTimeMs: number;
  fastSwitches: number; // <100ms
  normalSwitches: number; // 100-200ms
  slowSwitches: number; // >200ms
  cacheHitRate: number; // 0-100%
  lastSwitchAt: number;
}

/**
 * Concurrent workspace state
 */
export interface ConcurrentWorkspace {
  workspaceId: string;
  userId: string;
  isActive: boolean;
  switchedInAt: number;
  switchedOutAt?: number;
}

/**
 * Hot switch service configuration
 */
export interface HotSwitchServiceConfig {
  enableIndexedDB: boolean;
  maxConcurrentWorkspaces: number;
  cacheTimeToLiveMs: number;
  preloadNextWorkspace: boolean;
  compressionEnabled: boolean;
  encryptionEnabled: boolean;
  maxCacheSize: number; // MB
  maxStatisticsSize: number;
  maxAuditLogSize: number;
  storageBackend: 'memory' | 'indexeddb' | 'localstorage';
}

/**
 * Switch performance metric
 */
export interface SwitchPerformanceMetric {
  id: string;
  fromWorkspaceId: string;
  toWorkspaceId: string;
  userId: string;
  switchStartAt: number;
  switchEndAt: number;
  duration: number;
  contextSaveTimeMs: number;
  contextRestoreTimeMs: number;
  indexedDBWriteMs?: number;
  indexedDBReadMs?: number;
  stateSize: number;
  cacheHit: boolean;
}

/**
 * Audit log entry for switching
 */
export interface HotSwitchAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'workspace-switch' | 'cache-write' | 'cache-read' | 'preload' | 'evict';
  status: 'success' | 'failure';
  fromWorkspaceId?: string;
  toWorkspaceId?: string;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
  details: {
    switchTimeMs?: number;
    stateSize?: number;
    cacheHit?: boolean;
    reason?: string;
    [key: string]: unknown;
  };
}

/**
 * Preload hint
 */
export interface PreloadHint {
  workspaceId: string;
  priority: number; // 0-10
  reason: string;
  expiresAt: number;
}
