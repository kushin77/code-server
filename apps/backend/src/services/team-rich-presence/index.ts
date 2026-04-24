/**
 * @file        apps/backend/src/services/team-rich-presence/index.ts
 * @module      collaboration/presence
 * @description Rich Presence service for real-time team activity awareness
 *
 * Tracks and broadcasts presence state across team members: online/offline, idle/active,
 * current file/line, meeting status, and custom status message.
 */

import { EventEmitter } from 'events';

/**
 * Presence state for a team member
 */
export enum PresenceState {
  ONLINE = 'online',
  IDLE = 'idle',
  IN_MEETING = 'in-meeting',
  DO_NOT_DISTURB = 'dnd',
  OFFLINE = 'offline',
}

/**
 * User presence information
 */
export interface UserPresence {
  userId: string;
  teamId: string;
  state: PresenceState;
  lastActive: number; // timestamp
  currentFile?: string; // file path if editing
  currentLine?: number; // line number if editing
  statusMessage?: string; // custom status message
  statusEmoji?: string; // emoji for status (e.g., 🎤 for in-meeting)
  metadata: Record<string, unknown>; // extensible metadata
}

/**
 * Team activity summary
 */
export interface TeamActivitySummary {
  teamId: string;
  totalMembers: number;
  activeMembers: number;
  membersInMeeting: number;
  membersIdle: number;
  recentActivity: UserPresence[];
  timestamp: number;
}

/**
 * Presence snapshot for broadcast
 */
export interface PresenceSnapshot {
  presence: UserPresence[];
  timestamp: number;
}

/**
 * Rich Presence Service
 *
 * Manages real-time team presence state and activity broadcasting.
 * Automatically marks users as idle after inactivity period.
 */
export class TeamRichPresenceService extends EventEmitter {
  private presenceMap: Map<string, UserPresence> = new Map();
  private teamPresenceMap: Map<string, Set<string>> = new Map(); // teamId -> set of userIds
  private idleTimeoutMs: number = 300000; // 5 minutes
  private idleCheckInterval: NodeJS.Timer | null = null;

  constructor(idleTimeoutMs: number = 300000) {
    super();
    this.idleTimeoutMs = idleTimeoutMs;
    this.startIdleCheck();
  }

  /**
   * Update or create user presence
   */
  upsertPresence(
    userId: string,
    teamId: string,
    partial: Partial<UserPresence>,
  ): UserPresence {
    const existingKey = `${teamId}:${userId}`;
    const existing = this.presenceMap.get(existingKey);

    const presence: UserPresence = {
      userId,
      teamId,
      state: partial.state || PresenceState.ONLINE,
      lastActive: Date.now(),
      currentFile: partial.currentFile,
      currentLine: partial.currentLine,
      statusMessage: partial.statusMessage,
      statusEmoji: partial.statusEmoji,
      metadata: partial.metadata || {},
    };

    this.presenceMap.set(existingKey, presence);

    // Add to team set
    if (!this.teamPresenceMap.has(teamId)) {
      this.teamPresenceMap.set(teamId, new Set());
    }
    this.teamPresenceMap.get(teamId)!.add(userId);

    this.emit('presenceUpdated', { presence, isNewUser: !existing });

    return presence;
  }

  /**
   * Get presence for a specific user
   */
  getPresence(userId: string, teamId: string): UserPresence | undefined {
    const key = `${teamId}:${userId}`;
    return this.presenceMap.get(key);
  }

  /**
   * Get all presence for a team
   */
  listTeamPresence(teamId: string): UserPresence[] {
    const userIds = this.teamPresenceMap.get(teamId);
    if (!userIds) return [];

    return Array.from(userIds)
      .map((userId) => this.presenceMap.get(`${teamId}:${userId}`))
      .filter((p): p is UserPresence => p !== undefined);
  }

  /**
   * Get team activity summary
   */
  getTeamActivitySummary(teamId: string): TeamActivitySummary {
    const presence = this.listTeamPresence(teamId);
    const now = Date.now();

    const active = presence.filter((p) => p.state !== PresenceState.OFFLINE && p.state !== PresenceState.IDLE);
    const inMeeting = presence.filter((p) => p.state === PresenceState.IN_MEETING);
    const idle = presence.filter((p) => p.state === PresenceState.IDLE);

    return {
      teamId,
      totalMembers: presence.length,
      activeMembers: active.length,
      membersInMeeting: inMeeting.length,
      membersIdle: idle.length,
      recentActivity: presence.slice(0, 10), // Return recent 10
      timestamp: now,
    };
  }

  /**
   * Mark user as meeting (DND + meeting state)
   */
  setUserInMeeting(userId: string, teamId: string, inMeeting: boolean): UserPresence {
    const currentPresence = this.getPresence(userId, teamId);
    const newState = inMeeting ? PresenceState.IN_MEETING : PresenceState.ONLINE;
    const emoji = inMeeting ? '🎤' : undefined;

    return this.upsertPresence(userId, teamId, {
      ...currentPresence,
      state: newState,
      statusEmoji: emoji,
      statusMessage: inMeeting ? 'In a meeting' : undefined,
    });
  }

  /**
   * Update user's current editing location
   */
  updateEditorPosition(userId: string, teamId: string, filePath: string, lineNumber?: number): UserPresence {
    const currentPresence = this.getPresence(userId, teamId);

    return this.upsertPresence(userId, teamId, {
      ...currentPresence,
      currentFile: filePath,
      currentLine: lineNumber,
    });
  }

  /**
   * Set custom status message
   */
  setUserStatus(
    userId: string,
    teamId: string,
    message: string,
    emoji?: string,
  ): UserPresence {
    const currentPresence = this.getPresence(userId, teamId);

    return this.upsertPresence(userId, teamId, {
      ...currentPresence,
      statusMessage: message,
      statusEmoji: emoji,
    });
  }

  /**
   * Mark user as offline
   */
  removePresence(userId: string, teamId: string): void {
    const key = `${teamId}:${userId}`;
    const presence = this.presenceMap.get(key);

    if (presence) {
      presence.state = PresenceState.OFFLINE;
      presence.lastActive = Date.now();
      this.emit('presenceRemoved', { userId, teamId });
    }
  }

  /**
   * Get presence snapshot for broadcasting
   */
  getPresenceSnapshot(teamId: string): PresenceSnapshot {
    return {
      presence: this.listTeamPresence(teamId),
      timestamp: Date.now(),
    };
  }

  /**
   * Check for idle users and update state
   */
  private checkIdle(): void {
    const now = Date.now();
    const idleThreshold = now - this.idleTimeoutMs;

    for (const [key, presence] of this.presenceMap.entries()) {
      if (
        presence.state !== PresenceState.OFFLINE &&
        presence.state !== PresenceState.IDLE &&
        presence.lastActive < idleThreshold
      ) {
        presence.state = PresenceState.IDLE;
        this.emit('presenceUpdated', { presence, becameIdle: true });
      }
    }
  }

  /**
   * Start automatic idle checking
   */
  private startIdleCheck(): void {
    this.idleCheckInterval = setInterval(() => this.checkIdle(), 60000); // Check every minute
  }

  /**
   * Stop idle checking (for cleanup)
   */
  stopIdleCheck(): void {
    if (this.idleCheckInterval) {
      clearInterval(this.idleCheckInterval);
      this.idleCheckInterval = null;
    }
  }

  /**
   * Clean up resources
   */
  destroy(): void {
    this.stopIdleCheck();
    this.presenceMap.clear();
    this.teamPresenceMap.clear();
  }
}

export default TeamRichPresenceService;
