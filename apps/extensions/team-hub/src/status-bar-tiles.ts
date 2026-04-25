// @file        apps/extensions/team-hub/src/status-bar-tiles.ts
// @module      collab/status-bar
// @description Customizable status bar tiles with team metrics
// @governance  GOV-002: IaC, immutable, idempotent
// Issues #1055, #1141: [Collab-7.8] Customizable status bar tiles with team metrics

import * as vscode from "vscode";
import type { TeamHubUser } from "./types";

export type TileType =
  | "online-count"        // # of online team members
  | "same-file-count"     // # of members in same file
  | "active-meetings"     // # of active meeting modes
  | "session-cost"        // Current session cost ($)
  | "team-velocity"       // Commits/PRs in last 24h
  | "alert-count"         // Active alert count from Grafana
  | "custom-text";        // User-defined static text

export interface TileConfig {
  id: string;
  type: TileType;
  label?: string;             // Override default label
  position: "left" | "right";
  priority: number;           // Higher = closer to center
  enabled: boolean;
  command?: string;           // Command to run on click
}

export interface TileState {
  text: string;
  tooltip: string;
  color?: vscode.ThemeColor;
  backgroundColor?: vscode.ThemeColor;
}

export class StatusBarTileManager {
  private _tiles: Map<string, {
    config: TileConfig;
    item: vscode.StatusBarItem;
    state: TileState;
  }> = new Map();
  private _updateInterval: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly presenceSidecarUrl: string) {}

  // ── Register tiles from config ───────────────────────────────────────────

  registerDefaultTiles(ctx: vscode.ExtensionContext): void {
    const defaults: TileConfig[] = [
      {
        id: "online-count",
        type: "online-count",
        position: "left",
        priority: 90,
        enabled: true,
        command: "teamHub.workspaceMap.show",
      },
      {
        id: "same-file",
        type: "same-file-count",
        position: "left",
        priority: 89,
        enabled: true,
      },
      {
        id: "session-cost",
        type: "session-cost",
        position: "right",
        priority: 88,
        enabled: true,
        command: "teamHub.cost.showReport",
      },
    ];

    for (const config of defaults) {
      this.addTile(ctx, config);
    }
  }

  // ── Add/remove individual tiles ───────────────────────────────────────────

  addTile(ctx: vscode.ExtensionContext, config: TileConfig): void {
    if (this._tiles.has(config.id)) return;

    const item = vscode.window.createStatusBarItem(
      config.position === "left"
        ? vscode.StatusBarAlignment.Left
        : vscode.StatusBarAlignment.Right,
      config.priority
    );

    if (config.command) {
      item.command = config.command;
    }

    const state: TileState = { text: "…", tooltip: "" };
    this._tiles.set(config.id, { config, item, state });

    if (config.enabled) {
      item.show();
    }

    ctx.subscriptions.push(item);
  }

  removeTile(id: string): void {
    const tile = this._tiles.get(id);
    if (tile) {
      tile.item.hide();
      tile.item.dispose();
      this._tiles.delete(id);
    }
  }

  toggleTile(id: string): void {
    const tile = this._tiles.get(id);
    if (!tile) return;
    tile.config.enabled = !tile.config.enabled;
    if (tile.config.enabled) {
      tile.item.show();
    } else {
      tile.item.hide();
    }
  }

  // ── Update tile data from presence snapshot ───────────────────────────────

  update(data: {
    users: TeamHubUser[];
    currentFile?: string;
    sessionCostUsd?: number;
    activeMeetings?: number;
  }): void {
    for (const [id, tile] of this._tiles) {
      if (!tile.config.enabled) continue;

      switch (tile.config.type) {
        case "online-count": {
          const online = data.users.filter((u) => u.status === "online").length;
          tile.item.text = `$(person) ${online}`;
          tile.item.tooltip = `${online} team member${online !== 1 ? "s" : ""} online`;
          break;
        }

        case "same-file-count": {
          const sameFile = data.users.filter(
            (u) => u.currentFile && u.currentFile === data.currentFile
          ).length;
          if (sameFile > 0) {
            tile.item.text = `$(eye) ${sameFile}`;
            tile.item.tooltip = `${sameFile} teammate${sameFile !== 1 ? "s" : ""} in this file`;
            tile.item.backgroundColor = new vscode.ThemeColor(
              "statusBarItem.warningBackground"
            );
          } else {
            tile.item.text = "";
            tile.item.hide();
            continue;
          }
          break;
        }

        case "active-meetings": {
          const meetings = data.activeMeetings ?? 0;
          if (meetings > 0) {
            tile.item.text = `$(call-incoming) ${meetings}`;
            tile.item.tooltip = `${meetings} active meeting${meetings !== 1 ? "s" : ""}`;
          } else {
            tile.item.text = "";
            tile.item.hide();
            continue;
          }
          break;
        }

        case "session-cost": {
          const cost = data.sessionCostUsd ?? 0;
          if (cost > 0) {
            tile.item.text = `$(clock) $${cost.toFixed(3)}`;
            tile.item.tooltip = `Current session cost: $${cost.toFixed(4)}`;
          } else {
            tile.item.hide();
            continue;
          }
          break;
        }

        case "custom-text": {
          if (tile.config.label) {
            tile.item.text = tile.config.label;
          }
          break;
        }
      }

      if (tile.config.enabled) {
        tile.item.show();
      }
    }
  }

  dispose(): void {
    if (this._updateInterval) clearInterval(this._updateInterval);
    for (const tile of this._tiles.values()) {
      tile.item.dispose();
    }
    this._tiles.clear();
  }
}

// ── VSCode Command Registration ───────────────────────────────────────────────

export function registerStatusBarTileCommands(
  ctx: vscode.ExtensionContext,
  manager: StatusBarTileManager
): void {
  ctx.subscriptions.push(
    vscode.commands.registerCommand(
      "teamHub.tiles.customize",
      async () => {
        const tiles = [
          { label: "Online Team Count", id: "online-count" },
          { label: "Same-File Co-workers", id: "same-file" },
          { label: "Session Cost", id: "session-cost" },
          { label: "Active Meetings", id: "active-meetings" },
        ];

        const selected = await vscode.window.showQuickPick(
          tiles.map((t) => ({ ...t, picked: true })),
          {
            title: "Customize Status Bar Tiles",
            placeHolder: "Select tiles to show",
            canPickMany: true,
          }
        );

        if (!selected) return;

        const selectedIds = new Set(selected.map((t) => t.id));
        for (const tile of tiles) {
          if (selectedIds.has(tile.id)) {
            manager.toggleTile(tile.id);   // Show
          }
        }
      }
    )
  );
}
