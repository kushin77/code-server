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
export var PresenceState;
(function (PresenceState) {
    PresenceState["ONLINE"] = "online";
    PresenceState["IDLE"] = "idle";
    PresenceState["IN_MEETING"] = "in-meeting";
    PresenceState["DO_NOT_DISTURB"] = "dnd";
    PresenceState["OFFLINE"] = "offline";
})(PresenceState || (PresenceState = {}));
/**
 * Rich Presence Service
 *
 * Manages real-time team presence state and activity broadcasting.
 * Automatically marks users as idle after inactivity period.
 */
export class TeamRichPresenceService extends EventEmitter {
    constructor(idleTimeoutMs = 300000) {
        super();
        this.presenceMap = new Map();
        this.teamPresenceMap = new Map(); // teamId -> set of userIds
        this.idleTimeoutMs = 300000; // 5 minutes
        this.idleCheckInterval = null;
        this.idleTimeoutMs = idleTimeoutMs;
        this.startIdleCheck();
    }
    /**
     * Update or create user presence
     */
    upsertPresence(userId, teamId, partial) {
        const existingKey = `${teamId}:${userId}`;
        const existing = this.presenceMap.get(existingKey);
        const presence = {
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
        this.teamPresenceMap.get(teamId).add(userId);
        this.emit('presenceUpdated', { presence, isNewUser: !existing });
        return presence;
    }
    /**
     * Get presence for a specific user
     */
    getPresence(userId, teamId) {
        const key = `${teamId}:${userId}`;
        return this.presenceMap.get(key);
    }
    /**
     * Get all presence for a team
     */
    listTeamPresence(teamId) {
        const userIds = this.teamPresenceMap.get(teamId);
        if (!userIds)
            return [];
        return Array.from(userIds)
            .map((userId) => this.presenceMap.get(`${teamId}:${userId}`))
            .filter((p) => p !== undefined);
    }
    /**
     * Get team activity summary
     */
    getTeamActivitySummary(teamId) {
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
    setUserInMeeting(userId, teamId, inMeeting) {
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
    updateEditorPosition(userId, teamId, filePath, lineNumber) {
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
    setUserStatus(userId, teamId, message, emoji) {
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
    removePresence(userId, teamId) {
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
    getPresenceSnapshot(teamId) {
        return {
            presence: this.listTeamPresence(teamId),
            timestamp: Date.now(),
        };
    }
    /**
     * Check for idle users and update state
     */
    checkIdle() {
        const now = Date.now();
        const idleThreshold = now - this.idleTimeoutMs;
        for (const [key, presence] of this.presenceMap.entries()) {
            if (presence.state !== PresenceState.OFFLINE &&
                presence.state !== PresenceState.IDLE &&
                presence.lastActive < idleThreshold) {
                presence.state = PresenceState.IDLE;
                this.emit('presenceUpdated', { presence, becameIdle: true });
            }
        }
    }
    /**
     * Start automatic idle checking
     */
    startIdleCheck() {
        this.idleCheckInterval = setInterval(() => this.checkIdle(), 60000); // Check every minute
    }
    /**
     * Stop idle checking (for cleanup)
     */
    stopIdleCheck() {
        if (this.idleCheckInterval) {
            clearInterval(this.idleCheckInterval);
            this.idleCheckInterval = null;
        }
    }
    /**
     * Clean up resources
     */
    destroy() {
        this.stopIdleCheck();
        this.presenceMap.clear();
        this.teamPresenceMap.clear();
    }
}
export default TeamRichPresenceService;
//# sourceMappingURL=index.js.map