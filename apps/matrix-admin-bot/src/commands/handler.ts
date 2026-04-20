/**
 * @file        apps/matrix-admin-bot/src/commands/handler.ts
 * @module      matrix/admin-bot/commands
 * @description Routes and handles admin commands
 */

import type { MatrixClient } from "matrix-bot-sdk";
import type { Logger } from "pino";
import type { TemplateManager } from "../services/template-manager.js";
import type { RetentionManager } from "../services/retention-manager.js";
import type { AuditLogger } from "../services/audit-logger.js";

interface CommandContext {
  client: MatrixClient;
  roomId: string;
  eventId: string;
  sender: string;
  command: string;
  templateManager: TemplateManager;
  retentionManager: RetentionManager;
  auditLogger: AuditLogger;
  logger: Logger;
}

async function handleAdminCommand(context: CommandContext): Promise<void> {
  const { command, client, roomId, eventId, sender, templateManager, retentionManager, logger } = context;

  const [cmd, ...args] = command.trim().split(/\s+/);

  switch (cmd.toLowerCase()) {
    case "create-team":
      await handleCreateTeam(context, args);
      break;

    case "create-project":
      await handleCreateProject(context, args);
      break;

    case "archive":
      await handleArchiveRoom(context, args);
      break;

    case "retention":
      await handleSetRetention(context, args);
      break;

    case "list-templates":
      await handleListTemplates(context);
      break;

    case "members":
      await handleListMembers(context, args);
      break;

    case "help":
      await handleHelp(context);
      break;

    default:
      await sendReply(client, roomId, eventId, `Unknown command: ${cmd}. Type !admin help for usage.`);
  }
}

async function handleCreateTeam(context: CommandContext, args: string[]): Promise<void> {
  if (args.length === 0) {
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      "Usage: !admin create-team <name>"
    );
    return;
  }

  const teamName = args.join(" ");
  context.logger.info({ teamName, sender: context.sender }, "Creating team space");

  try {
    const roomId = await context.templateManager.createFromTemplate("team-default", {
      team_name: teamName,
      created_by: context.sender,
    });

    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✓ Team space created: ${teamName}\nRoom: ${roomId}`
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    context.logger.error(error, "Failed to create team");
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✗ Failed to create team: ${message}`
    );
  }
}

async function handleCreateProject(context: CommandContext, args: string[]): Promise<void> {
  if (args.length === 0) {
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      "Usage: !admin create-project <name>"
    );
    return;
  }

  const projectName = args.join(" ");
  context.logger.info({ projectName, sender: context.sender }, "Creating project space");

  try {
    const roomId = await context.templateManager.createFromTemplate("project-default", {
      project_name: projectName,
      created_by: context.sender,
    });

    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✓ Project space created: ${projectName}\nRoom: ${roomId}`
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    context.logger.error(error, "Failed to create project");
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✗ Failed to create project: ${message}`
    );
  }
}

async function handleArchiveRoom(context: CommandContext, args: string[]): Promise<void> {
  if (args.length === 0) {
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      "Usage: !admin archive <room_id>"
    );
    return;
  }

  const targetRoomId = args[0];
  context.logger.info({ targetRoomId, sender: context.sender }, "Archiving room");

  try {
    // Get room info - use state event lookup instead
    let roomName = targetRoomId;
    try {
      const stateEvent = await (context.client as any).getRoomState(targetRoomId, "m.room.name", "");
      if (stateEvent && stateEvent.name) {
        roomName = stateEvent.name;
      }
    } catch {
      // If we can't get room name, use room ID
    }

    // Set join rule to "knock" to prevent new joins
    await context.client.sendStateEvent(
      targetRoomId,
      "m.room.join_rules",
      "",
      { join_rule: "knock" }
    );

    // Send notification to room
    await context.client.sendMessage(targetRoomId, {
      msgtype: "m.text",
      body: "This room has been archived and is no longer active.",
    });

    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✓ Room archived: ${roomName}`
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    context.logger.error(error, "Failed to archive room");
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✗ Failed to archive room: ${message}`
    );
  }
}

async function handleSetRetention(context: CommandContext, args: string[]): Promise<void> {
  if (args.length < 2) {
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      "Usage: !admin retention <room_id> <days>"
    );
    return;
  }

  const targetRoomId = args[0];
  const days = parseInt(args[1], 10);

  if (isNaN(days) || days < 1) {
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      "Invalid retention days (must be >= 1)"
    );
    return;
  }

  context.logger.info({ targetRoomId, days, sender: context.sender }, "Setting retention");

  try {
    await context.retentionManager.setRetention(targetRoomId, days);
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✓ Retention policy set: ${days} days`
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    context.logger.error(error, "Failed to set retention");
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✗ Failed to set retention: ${message}`
    );
  }
}

async function handleListTemplates(context: CommandContext): Promise<void> {
  const templates = context.templateManager.listTemplates();
  const templateList = templates
    .map((t) => `  • **${t.name}**: ${t.description}`)
    .join("\n");

  await sendReply(
    context.client,
    context.roomId,
    context.eventId,
    `Available templates:\n${templateList}`
  );
}

async function handleListMembers(context: CommandContext, args: string[]): Promise<void> {
  if (args.length === 0) {
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      "Usage: !admin members <room_id>"
    );
    return;
  }

  const targetRoomId = args[0];
  context.logger.info({ targetRoomId }, "Listing room members");

  try {
    const members = await context.client.getRoomMembers(targetRoomId);
    const memberList = members
      .slice(0, 20) // Show first 20
      .map((m) => `  • ${(m as any).state_key || (m as any).user_id || m}`)
      .join("\n");

    const more = members.length > 20 ? `\n... and ${members.length - 20} more` : "";
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `Members (${members.length}):\n${memberList}${more}`
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    context.logger.error(error, "Failed to list members");
    await sendReply(
      context.client,
      context.roomId,
      context.eventId,
      `✗ Failed to list members: ${message}`
    );
  }
}

async function handleHelp(context: CommandContext): Promise<void> {
  const help = `
**Admin Bot Commands:**

**Space Management:**
• \`!admin create-team <name>\` - Create new team space
• \`!admin create-project <name>\` - Create new project space
• \`!admin archive <room_id>\` - Archive a room

**Policies:**
• \`!admin retention <room_id> <days>\` - Set retention policy

**Information:**
• \`!admin list-templates\` - Show available templates
• \`!admin members <room_id>\` - List room members
• \`!admin help\` - Show this help message

For more info, see the Matrix governance documentation.
`;

  await sendReply(context.client, context.roomId, context.eventId, help.trim());
}

async function sendReply(
  client: MatrixClient,
  roomId: string,
  inReplyTo: string,
  text: string
): Promise<void> {
  try {
    const htmlText = text
      .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
      .replace(/`(.*?)`/g, "<code>$1</code>")
      .replace(/\n/g, "<br>");

    await client.sendMessage(roomId, {
      msgtype: "m.text",
      body: text,
      format: "org.matrix.custom.html",
      formatted_body: htmlText,
      "m.relates_to": {
        "m.in_reply_to": {
          event_id: inReplyTo,
        },
      },
    });
  } catch (error) {
    console.error("Failed to send message:", error);
  }
}

export { handleAdminCommand };
