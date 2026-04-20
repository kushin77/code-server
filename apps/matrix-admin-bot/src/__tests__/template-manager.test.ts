/**
 * @file        apps/matrix-admin-bot/src/__tests__/template-manager.test.ts
 * @module      matrix/admin-bot/__tests__
 * @description Unit tests for TemplateManager
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { MatrixClient } from "matrix-bot-sdk";
import { TemplateManager } from "../services/template-manager.js";

describe("TemplateManager", () => {
  let mockClient: MatrixClient;
  let manager: TemplateManager;

  beforeEach(() => {
    mockClient = {
      createRoom: vi.fn(),
    } as unknown as MatrixClient;
    manager = new TemplateManager(mockClient);
  });

  describe("listTemplates", () => {
    it("should list all available templates", () => {
      const templates = manager.listTemplates();

      expect(templates).toHaveLength(3);
      expect(templates[0].name).toBeDefined();
      expect(templates[0].description).toBeDefined();
    });

    it("should include team-default template", () => {
      const templates = manager.listTemplates();
      const teamTemplate = templates.find((t) => t.name === "team-default");

      expect(teamTemplate).toBeDefined();
      expect(teamTemplate?.description).toContain("Team");
    });

    it("should include project-default template", () => {
      const templates = manager.listTemplates();
      const projectTemplate = templates.find((t) => t.name === "project-default");

      expect(projectTemplate).toBeDefined();
      expect(projectTemplate?.description).toContain("project");
    });
  });

  describe("getTemplate", () => {
    it("should return template if exists", () => {
      const template = manager.getTemplate("team-default");

      expect(template).toBeDefined();
      expect(template?.name).toBe("team-default");
    });

    it("should return undefined for unknown template", () => {
      const template = manager.getTemplate("unknown");

      expect(template).toBeUndefined();
    });
  });

  describe("createFromTemplate", () => {
    it("should create room with interpolated variables", async () => {
      const mockRoomId = "!room123:example.com";
      vi.mocked(mockClient.createRoom).mockResolvedValue(mockRoomId);

      const result = await manager.createFromTemplate("team-default", {
        team_name: "Engineering",
      });

      expect(result).toBe(mockRoomId);
      expect(mockClient.createRoom).toHaveBeenCalled();
    });

    it("should throw error for unknown template", async () => {
      await expect(
        manager.createFromTemplate("unknown-template", {})
      ).rejects.toThrow("Unknown template");
    });

    it("should use correct retention policy", async () => {
      const mockRoomId = "!room123:example.com";
      vi.mocked(mockClient.createRoom).mockResolvedValue(mockRoomId);

      await manager.createFromTemplate("team-default", {
        team_name: "Engineering",
      });

      const callArgs = vi.mocked(mockClient.createRoom).mock.calls[0][0] as any;
      expect(callArgs.initial_state).toContainEqual(
        expect.objectContaining({
          type: "m.room.retention",
        })
      );
    });
  });
});
