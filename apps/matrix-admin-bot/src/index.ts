#!/usr/bin/env node
/**
 * @file        apps/matrix-admin-bot/src/index.ts
 * @module      matrix/admin-bot
 * @description Matrix admin bot for space templates, governance, and moderation
 * 
 * Provides:
 * - Space/room template creation from admin commands
 * - Auto-join configuration for organization spaces
 * - Retention policy management
 * - Audit logging of administrative actions
 * - Optional: Content filtering, rate limiting, moderation
 */

import {
  MatrixClient,
  AutojoinRoomsMixin,
  RichReply,
} from "matrix-bot-sdk";
import { Logger } from "pino";
import pino from "pino";
import { TemplateManager } from "./services/template-manager.js";
import { RetentionManager } from "./services/retention-manager.js";
import { AuditLogger } from "./services/audit-logger.js";
import { ModerationManager } from "./services/moderation-manager.js";
import { handleAdminCommand } from "./commands/handler.js";

const logger: Logger = pino({
  level: process.env.LOG_LEVEL || "info",
});

interface AdminBotConfig {
  homeserverUrl: string;
  accessToken: string;
  adminUserId: string;
  databaseUrl: string;
  auditRetentionDays: number;
}

class MatrixAdminBot {
  private client: MatrixClient;
  private templateManager: TemplateManager;
  private retentionManager: RetentionManager;
  private auditLogger: AuditLogger;
  private moderationManager: ModerationManager;
  private config: AdminBotConfig;

  constructor(config: AdminBotConfig) {
    this.config = config;
    this.client = new MatrixClient(config.homeserverUrl, config.accessToken);
    this.templateManager = new TemplateManager(this.client);
    this.retentionManager = new RetentionManager(
      this.client,
      config.databaseUrl
    );
    this.auditLogger = new AuditLogger(config.databaseUrl);
    this.moderationManager = new ModerationManager(this.client);
  }

  async initialize(): Promise<void> {
    logger.info("Initializing Matrix admin bot...");

    try {
      // Verify connection and credentials
      const profile = await this.client.getUserProfile(this.config.adminUserId);
      logger.info(
        { profile },
        `Connected as ${this.config.adminUserId}`
      );

      // Auto-join configured rooms
      AutojoinRoomsMixin.setupOnClient(this.client);

      // Set up message handler for admin commands
      this.client.on("room.message", async (roomId: string, event: any) => {
        await this.handleRoomMessage(roomId, event);
      });

      // Start listening for events
      logger.info("Starting event listener...");
      await this.client.start();
      logger.info("Matrix admin bot ready!");
    } catch (error) {
      logger.error(error, "Failed to initialize admin bot");
      throw error;
    }
  }

  private async handleRoomMessage(
    roomId: string,
    event: any
  ): Promise<void> {
    try {
      // Skip bot's own messages
      if (event.sender === this.config.adminUserId) {
        return;
      }

      const body = event.content?.body;
      if (!body) {
        return;
      }

      // Check if message is a command
      if (!body.startsWith("!admin ")) {
        return;
      }

      logger.info(
        { roomId, sender: event.sender, command: body },
        "Admin command received"
      );

      const command = body.substring("!admin ".length);

      // Check if sender is admin (for now, check against a list)
      const isAdmin = await this.isUserAdmin(event.sender, roomId);
      if (!isAdmin) {
        await this.sendReply(
          roomId,
          event.event_id,
          "You don't have permission to use admin commands."
        );
        return;
      }

      // Route command
      await handleAdminCommand({
        client: this.client,
        roomId,
        eventId: event.event_id,
        sender: event.sender,
        command,
        templateManager: this.templateManager,
        retentionManager: this.retentionManager,
        auditLogger: this.auditLogger,
        logger,
      });

      // Log the action
      await this.auditLogger.log({
        eventType: "admin_command",
        sender: event.sender,
        roomId,
        command,
        action: "executed",
      });
    } catch (error) {
      logger.error(error, "Error handling room message");
      await this.sendReply(
        roomId,
        event.event_id,
        `Error processing command: ${error instanceof Error ? error.message : "Unknown error"}`
      );
    }
  }

  private async sendReply(
    roomId: string,
    inReplyTo: string,
    text: string
  ): Promise<void> {
    try {
      const reply = RichReply.createFor(roomId, { event_id: inReplyTo }, text, text);
      await this.client.sendMessage(roomId, reply);
    } catch (error) {
      logger.error(error, `Failed to send reply to ${roomId}`);
    }
  }

  private async isUserAdmin(userId: string, roomId: string): Promise<boolean> {
    try {
      const state = await this.client.getRoomStateEvent(
        roomId,
        "m.room.power_levels",
        ""
      );
      const powerLevel =
        state.users?.[userId] ?? state.users_default ?? 0;
      return powerLevel >= 100;
    } catch {
      return false;
    }
  }

  async cleanup(): Promise<void> {
    logger.info("Shutting down admin bot...");
    try {
      await this.client.stop();
      await this.auditLogger.close();
      logger.info("Admin bot shut down successfully");
    } catch (error) {
      logger.error(error, "Error during shutdown");
    }
  }
}

// Main entry point
async function main(): Promise<void> {
  const config: AdminBotConfig = {
    homeserverUrl: process.env.MATRIX_HOMESERVER_URL || "http://localhost:8008",
    accessToken: process.env.MATRIX_ACCESS_TOKEN || "",
    adminUserId: process.env.MATRIX_ADMIN_USER || "@admin:localhost",
    databaseUrl: process.env.AUDIT_DATABASE_URL || "",
    auditRetentionDays: parseInt(process.env.AUDIT_RETENTION_DAYS || "90"),
  };

  if (!config.accessToken || !config.databaseUrl) {
    logger.error(
      "Missing required environment variables: MATRIX_ACCESS_TOKEN, AUDIT_DATABASE_URL"
    );
    process.exit(1);
  }

  const bot = new MatrixAdminBot(config);

  // Graceful shutdown
  process.on("SIGTERM", async () => {
    logger.info("SIGTERM received");
    await bot.cleanup();
    process.exit(0);
  });

  process.on("SIGINT", async () => {
    logger.info("SIGINT received");
    await bot.cleanup();
    process.exit(0);
  });

  try {
    await bot.initialize();
  } catch (error) {
    logger.error(error, "Fatal error initializing bot");
    process.exit(1);
  }
}

main().catch((error) => {
  logger.error(error, "Unhandled error in main");
  process.exit(1);
});

export { MatrixAdminBot };
