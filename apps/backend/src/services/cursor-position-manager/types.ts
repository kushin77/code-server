/**
 * Real-time Cursor Position Manager Types
 * @file        apps/backend/src/services/cursor-position-manager/types.ts
 * @module      services/cursor-position-manager
 * @description Type definitions for real-time cursor position tracking
 */

/**
 * Cursor position in a file
 */
export interface CursorPosition {
  line: number;
  column: number;
}

/**
 * User cursor state
 */
export interface UserCursorState {
  userId: string;
  userEmail: string;
  userName: string;
  fileId: string;
  position: CursorPosition;
  selectionStart?: CursorPosition;
  selectionEnd?: CursorPosition;
  lastUpdated: number;
  color?: string;
  isActive: boolean;
}

/**
 * Cursor update event
 */
export interface CursorUpdate {
  userId: string;
  fileId: string;
  position: CursorPosition;
  selectionStart?: CursorPosition;
  selectionEnd?: CursorPosition;
  timestamp: number;
}

/**
 * Cursor visibility settings
 */
export interface CursorVisibilitySettings {
  showOtherCursors: boolean;
  showSelections: boolean;
  showInactiveAfterMs: number; // Hide cursors inactive for this duration
  colorScheme: 'auto' | 'light' | 'dark' | 'custom';
  cursorSize: 'small' | 'medium' | 'large';
}

/**
 * Cursor synchronization state
 */
export interface CursorSyncState {
  fileId: string;
  timestamp: number;
  activeCursors: UserCursorState[];
  inactiveCursors: UserCursorState[];
  conflictingPositions: CursorConflict[];
}

/**
 * Cursor conflict (e.g., multiple users at same position)
 */
export interface CursorConflict {
  conflictId: string;
  fileId: string;
  position: CursorPosition;
  involvedUsers: string[];
  conflictType: 'same-position' | 'overlapping-selection';
  detectedAt: number;
  resolved: boolean;
}

/**
 * Cursor presence indicator
 */
export interface CursorPresence {
  fileId: string;
  activeCursorCount: number;
  inactiveCursorCount: number;
  totalParticipants: number;
  lastSyncTime: number;
}

/**
 * Cursor history entry
 */
export interface CursorHistoryEntry {
  timestamp: number;
  userId: string;
  fileId: string;
  fromPosition: CursorPosition;
  toPosition: CursorPosition;
  movementDistance: number; // Manhattan distance
}

/**
 * Cursor statistics
 */
export interface CursorStatistics {
  totalCursorsTracked: number;
  activeCursors: number;
  inactiveCursors: number;
  totalFiles: number;
  averageCursorMovementPerSecond: number;
  mostActiveCursor: { userId: string; moveCount: number } | null;
  conflictDetectionAccuracy: number;
}

/**
 * Cursor jump event
 */
export interface CursorJumpEvent {
  jumpId: string;
  userId: string;
  fromPosition: CursorPosition;
  toPosition: CursorPosition;
  fileId: string;
  reason: 'goto-definition' | 'goto-reference' | 'search' | 'quickfix' | 'manual' | 'auto-completion';
  timestamp: number;
}

/**
 * Viewport focus area
 */
export interface ViewportFocusArea {
  fileId: string;
  minLine: number;
  maxLine: number;
  minColumn: number;
  maxColumn: number;
}

/**
 * User viewport state
 */
export interface UserViewportState {
  userId: string;
  fileId: string;
  focusArea: ViewportFocusArea;
  zoom: number; // 1.0 = 100%
  lastUpdated: number;
}

/**
 * Cursor broadcast message
 */
export interface CursorBroadcast {
  broadcastId: string;
  fileId: string;
  cursorUpdates: CursorUpdate[];
  includedUsers: string[];
  timestamp: number;
  priority: 'low' | 'normal' | 'high';
}

/**
 * Cursor audit entry
 */
export interface CursorAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  fileId: string;
  details: Record<string, unknown>;
}

/**
 * Cursor Position Manager configuration
 */
export interface CursorPositionConfig {
  enableTracking: boolean;
  inactivityThreshold: number; // ms before marking inactive
  maxHistoryEntries: number;
  maxAuditEntries: number;
  conflictDetectionEnabled: boolean;
  broadcastInterval: number; // ms between broadcasts
  broadcastBatchSize: number;
}

/**
 * Cursor Position Manager Service interface
 */
export interface ICursorPositionService {
  // Cursor tracking
  updateCursorPosition(
    userId: string,
    userEmail: string,
    userName: string,
    fileId: string,
    position: CursorPosition,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  updateCursorSelection(
    userId: string,
    fileId: string,
    selectionStart: CursorPosition,
    selectionEnd: CursorPosition,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  // Position queries
  getCursorPosition(userId: string, fileId: string): CursorPosition | undefined;
  getCursorsInFile(fileId: string): UserCursorState[];
  getCursorsByUser(userId: string): UserCursorState[];
  getActiveCursors(fileId?: string): UserCursorState[];
  getInactiveCursors(fileId?: string): UserCursorState[];

  // Synchronization
  getSyncState(fileId: string): CursorSyncState;
  broadcastCursorUpdate(fileId: string, updates: CursorUpdate[], userId: string, ipAddress: string, userAgent: string): { success: boolean; broadcastId?: string };

  // Presence
  getPresence(fileId: string): CursorPresence;
  getUserPresence(userId: string): CursorPresence[];

  // Conflict detection
  detectConflicts(fileId: string): CursorConflict[];
  resolveConflict(conflictId: string, resolutionStrategy: 'none' | 'merge' | 'separate', userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Cursor jumps
  recordCursorJump(jump: Omit<CursorJumpEvent, 'jumpId' | 'timestamp'>, userId: string, ipAddress: string, userAgent: string): { success: boolean; jumpId?: string };
  getCursorJumps(userId: string, fileId?: string, limit?: number): CursorJumpEvent[];

  // Viewport management
  updateViewport(userId: string, fileId: string, focusArea: ViewportFocusArea, zoom: number, ipAddress: string, userAgent: string): { success: boolean };
  getViewport(userId: string, fileId: string): UserViewportState | undefined;

  // Visibility settings
  updateVisibilitySettings(settings: CursorVisibilitySettings, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  getVisibilitySettings(userId: string): CursorVisibilitySettings;

  // History
  getCursorHistory(fileId: string, userId?: string, limit?: number): CursorHistoryEntry[];
  clearCursorHistory(fileId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Statistics
  getStatistics(fileId?: string): CursorStatistics;
  getAuditLog(limit?: number): CursorAuditEntry[];

  // User management
  removeCursor(userId: string, fileId: string, ipAddress: string, userAgent: string): { success: boolean };
  removeUserFromFile(userId: string, fileId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Configuration
  updateConfig(config: Partial<CursorPositionConfig>): void;
  getConfig(): CursorPositionConfig;

  // Lifecycle
  shutdown(): void;
}
