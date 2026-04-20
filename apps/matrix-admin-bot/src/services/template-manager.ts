/**
 * @file        apps/matrix-admin-bot/src/services/template-manager.ts
 * @module      matrix/admin-bot/services
 * @description Manages space/room template creation
 */

import type { MatrixClient } from "matrix-bot-sdk";

interface SpaceTemplate {
  name: string;
  description: string;
  displayName: string;
  topic: string;
  joinRule: "public" | "knock" | "invite" | "private";
  inviteOnly: boolean;
  powerLevels: {
    users?: Record<string, number>;
    events?: Record<string, number>;
    eventsDefault?: number;
    stateDefault?: number;
    usersDefault?: number;
  };
  retentionDays: number;
}

const TEMPLATES: Record<string, SpaceTemplate> = {
  "team-default": {
    name: "team-default",
    description: "Team collaboration space",
    displayName: "Team: {team_name}",
    topic: "Team collaboration space",
    joinRule: "invite",
    inviteOnly: true,
    powerLevels: {
      events: {
        "m.room.avatar": 50,
        "m.room.retention": 50,
        "m.room.topic": 50,
        "m.room.name": 50,
      },
      eventsDefault: 0,
      stateDefault: 50,
      usersDefault: 0,
    },
    retentionDays: 90,
  },

  "project-default": {
    name: "project-default",
    description: "Temporary project space",
    displayName: "Project: {project_name}",
    topic: "Temporary project collaboration space",
    joinRule: "knock",
    inviteOnly: false,
    powerLevels: {
      eventsDefault: 10,
      stateDefault: 50,
      usersDefault: 0,
    },
    retentionDays: 30,
  },

  "public-announcements": {
    name: "public-announcements",
    description: "Organization announcements",
    displayName: "Announcements",
    topic: "Organization-wide announcements",
    joinRule: "public",
    inviteOnly: false,
    powerLevels: {
      eventsDefault: 0, // Read-only for regular users
      stateDefault: 100, // Only admins can modify
      usersDefault: 0,
    },
    retentionDays: 365,
  },
};

export class TemplateManager {
  constructor(private client: MatrixClient) {}

  /**
   * Create a room from a template
   */
  async createFromTemplate(
    templateName: string,
    variables: Record<string, string>
  ): Promise<string> {
    const template = TEMPLATES[templateName];
    if (!template) {
      throw new Error(`Unknown template: ${templateName}`);
    }

    const name = this.interpolate(template.displayName, variables);
    const topic = this.interpolate(template.topic, variables);

    try {
      const roomId = await this.client.createRoom({
        name,
        topic,
        preset: template.joinRule === "public" ? "public_chat" : "private_chat",
        join_rules: template.joinRule,
        power_level_content_override: {
          users: template.powerLevels.users || {},
          events: template.powerLevels.events || {},
          events_default: template.powerLevels.eventsDefault ?? 0,
          state_default: template.powerLevels.stateDefault ?? 50,
          users_default: template.powerLevels.usersDefault ?? 0,
        },
        initial_state: [
          // Retention policy
          {
            type: "m.room.retention",
            state_key: "",
            content: {
              max_lifetime: template.retentionDays * 24 * 60 * 60 * 1000,
            },
          },
          // Room metadata
          {
            type: "com.custom.template_metadata",
            state_key: "",
            content: {
              template_name: templateName,
              created_from_template: true,
              created_at: new Date().toISOString(),
            },
          },
        ],
      });

      return roomId;
    } catch (error) {
      throw new Error(
        `Failed to create room from template ${templateName}: ${error instanceof Error ? error.message : "Unknown error"}`
      );
    }
  }

  /**
   * List available templates
   */
  listTemplates(): Array<{ name: string; description: string; displayName: string }> {
    return Object.values(TEMPLATES).map((t) => ({
      name: t.name,
      description: t.description,
      displayName: t.displayName,
    }));
  }

  /**
   * Get template details
   */
  getTemplate(name: string): SpaceTemplate | undefined {
    return TEMPLATES[name];
  }

  /**
   * Interpolate variables in a template string
   * Converts {variable_name} to the corresponding value
   */
  private interpolate(
    template: string,
    variables: Record<string, string>
  ): string {
    return template.replace(/{(\w+)}/g, (match, key) => {
      return variables[key] || match;
    });
  }
}
