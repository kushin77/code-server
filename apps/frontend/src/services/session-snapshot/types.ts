/**
 * @file        apps/frontend/src/services/session-snapshot/types.ts
 * @module      collaboration/session-persistence
 * @description Type definitions for session snapshot persistence
 */

/**
 * Single file entry in snapshot
 */
export interface SnapshotFile {
  path: string;
  isDirty: boolean;
  cursorPosition: { line: number; column: number };
  scrollPosition: number;
  language?: string;
}

/**
 * Terminal session state
 */
export interface SnapshotTerminal {
  id: string;
  name: string;
  cwd: string;
  shellType: 'bash' | 'sh' | 'zsh' | 'powershell' | 'cmd';
  history: string[];
  isRunning: boolean;
}

/**
 * Debug session state
 */
export interface SnapshotDebugSession {
  id: string;
  name: string;
  type: string;
  state: 'idle' | 'running' | 'stopped' | 'paused';
  breakpoints: Array<{
    file: string;
    line: number;
    condition?: string;
  }>;
  variables?: Record<string, any>;
}

/**
 * Layout configuration
 */
export interface SnapshotLayout {
  mainPanelWidth: number;
  sidePanelWidth: number;
  bottomPanelHeight: number;
  sidebarVisible: boolean;
  bottomPanelVisible: boolean;
  activityBarPosition: 'left' | 'right';
  focusedPanel: 'main' | 'side' | 'bottom' | 'debug';
}

/**
 * Full session snapshot
 */
export interface SessionSnapshot {
  id: string;
  workspaceId: string;
  userId: string;
  createdAt: number;
  updatedAt: number;
  version: number; // For 10-version history
  label?: string; // User-friendly name like "Before refactor"
  
  // Core state
  layout: SnapshotLayout;
  openFiles: SnapshotFile[];
  selectedFile: string | null;
  terminals: SnapshotTerminal[];
  debugSessions: SnapshotDebugSession[];
  
  // Extension/settings state
  enabledExtensions: string[];
  disabledExtensions: string[];
  settings: Record<string, any>;
  
  // Metadata
  fileTreeExpanded: string[];
  recentFiles: string[];
  bookmarks: Array<{ path: string; label?: string }>;
  
  // Restore metadata
  restoreableIn: 'immediate' | 'quick' | 'full'; // SLA categories
  estimatedRestoreTimeMs: number;
  size: number; // bytes
}

/**
 * Snapshot metadata (lightweight, for listing)
 */
export interface SnapshotMetadata {
  id: string;
  workspaceId: string;
  createdAt: number;
  label?: string;
  version: number;
  fileCount: number;
  terminalCount: number;
  size: number;
  estimatedRestoreTimeMs: number;
}

/**
 * Snapshot list with pagination
 */
export interface SnapshotListResponse {
  snapshots: SnapshotMetadata[];
  total: number;
  page: number;
  pageSize: number;
}

/**
 * Restore options
 */
export interface RestoreOptions {
  includeFiles?: boolean;
  includeTerminals?: boolean;
  includeDebug?: boolean;
  includeSettings?: boolean;
  includeExtensions?: boolean;
  mergeWithCurrent?: boolean;
}

/**
 * Restore result with timing information
 */
export interface RestoreResult {
  snapshotId: string;
  success: boolean;
  filesRestored: number;
  terminalsRestored: number;
  settingsRestored: boolean;
  totalTimeMs: number;
  error?: string;
}
