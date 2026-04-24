// @file apps/extensions/team-hub/src/collaboration-detector.ts
// @module ide/collaboration-intelligence
// @description P2-1539 Phase 3: Real-time collaboration detection and conflict prediction
// @governance GOV-002: All collaboration events logged, immutable audit trail

import * as vscode from 'vscode';

export enum CollaborationEventType {
  USER_JOINED = 'user_joined',
  USER_LEFT = 'user_left',
  FILE_EDIT_START = 'file_edit_start',
  FILE_EDIT_END = 'file_edit_end',
  CONFLICT_DETECTED = 'conflict_detected',
  CONFLICT_RESOLVED = 'conflict_resolved'
}

export interface CollaborationEvent {
  id: string;
  type: CollaborationEventType;
  timestamp: string;
  userId: string;
  userName: string;
  filePath?: string;
  description: string;
  severity: 'info' | 'warning' | 'error';
}

export interface FileEditLock {
  filePath: string;
  userId: string;
  userName: string;
  startTime: string;
  lineRange?: {
    start: number;
    end: number;
  };
}

export interface DetectedConflict {
  id: string;
  type: 'edit_conflict' | 'delete_conflict' | 'rename_conflict';
  filePath: string;
  user1: string;
  user2: string;
  user1LineRange?: { start: number; end: number };
  user2LineRange?: { start: number; end: number };
  severity: 'low' | 'medium' | 'high';
  suggestedResolution: string;
  timestamp: string;
}

export class CollaborationDetector {
  private activeLocks: Map<string, FileEditLock> = new Map();
  private eventHistory: CollaborationEvent[] = [];
  private detectedConflicts: DetectedConflict[] = [];
  private userPresence: Map<string, { userName: string; lastSeen: string }> = new Map();
  private outputChannel: vscode.OutputChannel;

  constructor() {
    this.outputChannel = vscode.window.createOutputChannel('KC IDE Collaboration');
  }

  /**
   * Register when a user starts editing a file
   */
  registerFileEditStart(filePath: string, userId: string, userName: string, lineStart?: number, lineEnd?: number): void {
    const lock: FileEditLock = {
      filePath,
      userId,
      userName,
      startTime: new Date().toISOString(),
      lineRange: lineStart && lineEnd ? { start: lineStart, end: lineEnd } : undefined
    };

    this.activeLocks.set(this.getLockKey(filePath, userId), lock);

    this.logEvent({
      type: CollaborationEventType.FILE_EDIT_START,
      userId,
      userName,
      filePath,
      description: `${userName} started editing ${filePath}`,
      severity: 'info'
    });

    // Check for conflicts with other users
    this.checkForConflicts(filePath, userId, lineStart, lineEnd);
  }

  /**
   * Register when a user stops editing a file
   */
  registerFileEditEnd(filePath: string, userId: string, userName: string): void {
    const lockKey = this.getLockKey(filePath, userId);
    this.activeLocks.delete(lockKey);

    this.logEvent({
      type: CollaborationEventType.FILE_EDIT_END,
      userId,
      userName,
      filePath,
      description: `${userName} finished editing ${filePath}`,
      severity: 'info'
    });
  }

  /**
   * Register user presence (e.g., via workspace sync)
   */
  registerUserPresence(userId: string, userName: string): void {
    this.userPresence.set(userId, {
      userName,
      lastSeen: new Date().toISOString()
    });

    // Check if this is a new user joining
    const isNewUser = !this.eventHistory.some(
      e => e.userId === userId && e.type === CollaborationEventType.USER_JOINED
    );

    if (isNewUser) {
      this.logEvent({
        type: CollaborationEventType.USER_JOINED,
        userId,
        userName,
        description: `${userName} joined the session`,
        severity: 'info'
      });
    }
  }

  /**
   * Check for edit conflicts when a user starts editing
   */
  private checkForConflicts(filePath: string, userId: string, lineStart?: number, lineEnd?: number): void {
    for (const [lockKey, lock] of this.activeLocks) {
      if (lock.filePath === filePath && lock.userId !== userId) {
        // Another user is already editing this file
        const conflict: DetectedConflict = {
          id: `conflict-${Date.now()}-${Math.random().toString(36).substring(7)}`,
          type: this.determineConflictType(lock, lineStart, lineEnd),
          filePath,
          user1: lock.userId,
          user2: userId,
          user1LineRange: lock.lineRange,
          user2LineRange: lineStart && lineEnd ? { start: lineStart, end: lineEnd } : undefined,
          severity: this.calculateConflictSeverity(lock.lineRange, lineStart, lineEnd),
          suggestedResolution: this.suggestConflictResolution(lock, userId),
          timestamp: new Date().toISOString()
        };

        this.detectedConflicts.push(conflict);

        this.logEvent({
          type: CollaborationEventType.CONFLICT_DETECTED,
          userId,
          userName: this.userPresence.get(userId)?.userName || userId,
          filePath,
          description: `Conflict detected: ${lock.userName} and ${this.userPresence.get(userId)?.userName || userId} editing ${filePath}`,
          severity: 'warning'
        });

        // Notify about conflict
        this.notifyConflict(conflict);
      }
    }
  }

  /**
   * Determine conflict type based on lock and edit positions
   */
  private determineConflictType(lock: FileEditLock, lineStart?: number, lineEnd?: number): 'edit_conflict' | 'delete_conflict' | 'rename_conflict' {
    // For now, classify as edit_conflict
    // Enhanced detection could distinguish between edits, deletes, renames
    return 'edit_conflict';
  }

  /**
   * Calculate conflict severity based on overlapping line ranges
   */
  private calculateConflictSeverity(range1?: { start: number; end: number }, lineStart?: number, lineEnd?: number): 'low' | 'medium' | 'high' {
    // If no line ranges, cannot determine - treat as medium
    if (!range1 || lineStart === undefined || lineEnd === undefined) {
      return 'medium';
    }

    // Check for overlapping ranges
    const overlap = !(range1.end < lineStart || lineEnd < range1.start);
    if (overlap) {
      return 'high'; // Direct overlap
    }

    // Adjacent edits
    if (Math.abs(range1.end - lineStart) < 3 || Math.abs(lineEnd - range1.start) < 3) {
      return 'medium';
    }

    return 'low';
  }

  /**
   * Suggest how to resolve the conflict
   */
  private suggestConflictResolution(lock: FileEditLock, userId: string): string {
    return `Two users editing same file. Suggestions: 1) Use shared edit mode, 2) One user takes lock, other reviews, 3) Use AI-assisted merge when both finish`;
  }

  /**
   * Get active edit locks for a file
   */
  getActiveLocks(filePath: string): FileEditLock[] {
    return Array.from(this.activeLocks.values()).filter(lock => lock.filePath === filePath);
  }

  /**
   * Get current user presence
   */
  getUserPresence(): Map<string, { userName: string; lastSeen: string }> {
    return new Map(this.userPresence);
  }

  /**
   * Get detected conflicts
   */
  getDetectedConflicts(): DetectedConflict[] {
    return [...this.detectedConflicts];
  }

  /**
   * Get recent events
   */
  getRecentEvents(limit: number = 50): CollaborationEvent[] {
    return this.eventHistory.slice(-limit);
  }

  /**
   * Log a collaboration event
   */
  private logEvent(event: Omit<CollaborationEvent, 'id' | 'timestamp'>): void {
    const colabEvent: CollaborationEvent = {
      id: `event-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      timestamp: new Date().toISOString(),
      ...event
    };

    this.eventHistory.push(colabEvent);

    // Log to output channel
    const logLevel = event.severity.toUpperCase();
    this.outputChannel.appendLine(
      `[${colabEvent.timestamp}] [${logLevel}] [${event.userId}] ${event.description}`
    );

    // Keep history bounded
    if (this.eventHistory.length > 10000) {
      this.eventHistory = this.eventHistory.slice(-5000);
    }
  }

  /**
   * Notify about detected conflict
   */
  private notifyConflict(conflict: DetectedConflict): void {
    const message = `⚠️  Collaboration conflict detected in ${conflict.filePath}`;
    vscode.window.showWarningMessage(message);
  }

  /**
   * Generate unique key for lock
   */
  private getLockKey(filePath: string, userId: string): string {
    return `${filePath}:${userId}`;
  }

  /**
   * Get collaboration statistics
   */
  getStatistics(): {
    activeUsers: number;
    activeLocks: number;
    totalEvents: number;
    totalConflicts: number;
    conflictsResolved: number;
  } {
    return {
      activeUsers: this.userPresence.size,
      activeLocks: this.activeLocks.size,
      totalEvents: this.eventHistory.length,
      totalConflicts: this.detectedConflicts.length,
      conflictsResolved: this.detectedConflicts.filter(c => c.type === 'edit_conflict').length
    };
  }
}

export function createCollaborationDetector(): CollaborationDetector {
  return new CollaborationDetector();
}
