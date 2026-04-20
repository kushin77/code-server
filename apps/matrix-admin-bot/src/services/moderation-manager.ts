/**
 * @file        apps/matrix-admin-bot/src/services/moderation-manager.ts
 * @module      matrix/admin-bot/services
 * @description Moderation tooling for Matrix (content filters, rate limiting)
 */

import type { MatrixClient } from "matrix-bot-sdk";

interface ModerationConfig {
  contentFiltering?: {
    enabled: boolean;
    patterns: RegExp[];
    action: "warn" | "redact" | "ban";
  };
  rateLimiting?: {
    messagesPerMinute: number;
    action: "warn" | "mute" | "kick";
  };
}

interface UserRateLimit {
  messagesInWindow: number;
  windowStart: number;
}

export class ModerationManager {
  private config: ModerationConfig;
  private userRateLimits: Map<string, UserRateLimit> = new Map();

  constructor(
    private client: MatrixClient,
    config?: ModerationConfig
  ) {
    this.config = config || {
      contentFiltering: { enabled: false, patterns: [], action: "redact" },
      rateLimiting: { messagesPerMinute: 60, action: "warn" },
    };
  }

  /**
   * Check if content should be filtered
   */
  checkContentFilter(content: string): {
    filtered: boolean;
    action: "warn" | "redact" | "ban";
  } {
    if (!this.config.contentFiltering?.enabled) {
      return { filtered: false, action: "warn" };
    }

    for (const pattern of this.config.contentFiltering.patterns) {
      if (pattern.test(content)) {
        return {
          filtered: true,
          action: this.config.contentFiltering.action,
        };
      }
    }

    return { filtered: false, action: "warn" };
  }

  /**
   * Check rate limiting for a user
   */
  checkRateLimit(userId: string): {
    limited: boolean;
    action: "warn" | "mute" | "kick";
  } {
    if (!this.config.rateLimiting) {
      return { limited: false, action: "warn" };
    }

    const now = Date.now();
    const windowMs = 60_000; // 1 minute
    const limit = this.config.rateLimiting;

    let userLimit = this.userRateLimits.get(userId);

    // Initialize or reset window if needed
    if (!userLimit || now - userLimit.windowStart > windowMs) {
      userLimit = { messagesInWindow: 1, windowStart: now };
      this.userRateLimits.set(userId, userLimit);
      return { limited: false, action: "warn" };
    }

    // Increment message count
    userLimit.messagesInWindow++;

    // Check if exceeded limit
    if (userLimit.messagesInWindow > limit.messagesPerMinute) {
      return {
        limited: true,
        action: limit.action,
      };
    }

    return { limited: false, action: "warn" };
  }

  /**
   * Mute a user in a room for a duration
   */
  async muteUser(
    roomId: string,
    userId: string,
    durationMs: number
  ): Promise<void> {
    try {
      // Reduce user's power level temporarily
      const state = await this.client.getRoomStateEvent(
        roomId,
        "m.room.power_levels",
        ""
      );

      const users = state.users || {};
      users[userId] = -1; // Negative power level prevents posting

      await this.client.sendStateEvent(roomId, "m.room.power_levels", "", {
        ...state,
        users,
      });

      // Restore power level after duration
      setTimeout(async () => {
        const updatedState = await this.client.getRoomStateEvent(
          roomId,
          "m.room.power_levels",
          ""
        );
        const updatedUsers = updatedState.users || {};
        delete updatedUsers[userId];

        await this.client.sendStateEvent(
          roomId,
          "m.room.power_levels",
          "",
          {
            ...updatedState,
            users: updatedUsers,
          }
        );
      }, durationMs);
    } catch (error) {
      console.error("Failed to mute user:", error);
    }
  }

  /**
   * Ban a user from a room
   */
  async banUser(roomId: string, userId: string, reason?: string): Promise<void> {
    try {
      await this.client.ban(roomId, userId, reason);
    } catch (error) {
      console.error("Failed to ban user:", error);
      throw error;
    }
  }

  /**
   * Kick a user from a room
   */
  async kickUser(roomId: string, userId: string, reason?: string): Promise<void> {
    try {
      await this.client.kick(roomId, userId, reason);
    } catch (error) {
      console.error("Failed to kick user:", error);
      throw error;
    }
  }

  /**
   * Update moderation configuration
   */
  updateConfig(config: Partial<ModerationConfig>): void {
    this.config = { ...this.config, ...config };
  }

  /**
   * Get current moderation statistics
   */
  getStats(): {
    usersBeingRateLimited: number;
    contentFiltersActive: number;
  } {
    return {
      usersBeingRateLimited: this.userRateLimits.size,
      contentFiltersActive: this.config.contentFiltering?.patterns.length || 0,
    };
  }
}
