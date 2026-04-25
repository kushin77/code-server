// @file        apps/extensions/team-hub/src/workspace-map.ts
// @module      collab/presence
// @description Workspace map — visual overview of all active sessions and file navigation
// @governance  GOV-002: IaC, immutable, idempotent
// Issue #1112: [Collab-4.9] Workspace map - visual overview of all active sessions

import * as vscode from "vscode";
import type { TeamHubUser } from "./types";

export interface SessionNode {
  userId: string;
  displayName: string;
  status: string;
  currentFile?: string;
  currentLine?: number;
  currentTask?: string;
  workspace?: string;
  lastSeen: number;
}

// ── WebView Panel: Workspace Map ─────────────────────────────────────────────

export class WorkspaceMapPanel {
  private static _instance: WorkspaceMapPanel | undefined;
  private readonly _panel: vscode.WebviewPanel;
  private _users: TeamHubUser[] = [];
  private _disposables: vscode.Disposable[] = [];

  private constructor(private readonly ctx: vscode.ExtensionContext) {
    this._panel = vscode.window.createWebviewPanel(
      "teamHubWorkspaceMap",
      "Team Workspace Map",
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [ctx.extensionUri],
      }
    );

    this._panel.onDidDispose(() => {
      WorkspaceMapPanel._instance = undefined;
      this.dispose();
    }, null, this._disposables);

    this._panel.webview.onDidReceiveMessage(
      async (message) => {
        if (message.command === "openFile") {
          await this._openFile(message.file, message.line);
        }
      },
      null,
      this._disposables
    );
  }

  static show(ctx: vscode.ExtensionContext): WorkspaceMapPanel {
    if (WorkspaceMapPanel._instance) {
      WorkspaceMapPanel._instance._panel.reveal(vscode.ViewColumn.Beside);
      return WorkspaceMapPanel._instance;
    }
    const instance = new WorkspaceMapPanel(ctx);
    WorkspaceMapPanel._instance = instance;
    return instance;
  }

  updateUsers(users: TeamHubUser[]): void {
    this._users = users;
    this._panel.webview.html = this._buildHtml();
  }

  private async _openFile(filePath: string, line?: number): Promise<void> {
    if (!filePath) return;
    try {
      const doc = await vscode.workspace.openTextDocument(
        vscode.Uri.file(filePath)
      );
      const editor = await vscode.window.showTextDocument(
        doc,
        vscode.ViewColumn.One
      );
      if (line !== undefined) {
        const pos = new vscode.Position(Math.max(0, line - 1), 0);
        editor.revealRange(
          new vscode.Range(pos, pos),
          vscode.TextEditorRevealType.InCenter
        );
        editor.selection = new vscode.Selection(pos, pos);
      }
    } catch {
      vscode.window.showWarningMessage(`Cannot open file: ${filePath}`);
    }
  }

  private _buildHtml(): string {
    const online = this._users.filter((u) => u.status === "online");
    const away = this._users.filter((u) => u.status === "away");
    const offline = this._users.filter((u) => u.status === "offline");

    const renderUser = (user: TeamHubUser): string => {
      const dotColor =
        user.status === "online"
          ? "#4caf50"
          : user.status === "away"
          ? "#ff9800"
          : "#666";
      const fileLink =
        user.currentFile
          ? `<a href="#" class="file-link"
               onclick="vscode.postMessage({command:'openFile',file:'${escapeHtml(user.currentFile)}',line:${user.currentLine ?? 1}});return false;"
             >📄 ${escapeHtml(shortFileName(user.currentFile))}${user.currentLine ? `:${user.currentLine}` : ""}</a>`
          : "<span class='no-file'>No file open</span>";

      return `<div class="user-card">
        <div class="user-header">
          <span class="status-dot" style="background:${dotColor}"></span>
          <strong>${escapeHtml(user.displayName)}</strong>
        </div>
        <div class="user-file">${fileLink}</div>
        ${user.currentTask ? `<div class="user-task">✅ ${escapeHtml(user.currentTask)}</div>` : ""}
        ${user.customStatus ? `<div class="user-status">💬 ${escapeHtml(user.customStatus)}</div>` : ""}
        <div class="user-time">${formatLastSeen(user.lastSeen)}</div>
      </div>`;
    };

    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Team Workspace Map</title>
<style>
  body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); padding: 12px; }
  h2 { font-size: 14px; margin: 0 0 12px; color: var(--vscode-textLink-foreground); }
  .section { margin-bottom: 16px; }
  .section-title { font-size: 11px; text-transform: uppercase; color: var(--vscode-descriptionForeground); margin-bottom: 8px; }
  .user-card { background: var(--vscode-editor-inactiveSelectionBackground); border-radius: 4px; padding: 8px 10px; margin-bottom: 6px; }
  .user-header { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; }
  .status-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .user-file { font-size: 12px; margin: 2px 0; }
  .file-link { color: var(--vscode-textLink-foreground); text-decoration: none; }
  .file-link:hover { text-decoration: underline; }
  .no-file { color: var(--vscode-descriptionForeground); font-style: italic; font-size: 11px; }
  .user-task, .user-status { font-size: 11px; color: var(--vscode-descriptionForeground); margin-top: 2px; }
  .user-time { font-size: 10px; color: var(--vscode-descriptionForeground); margin-top: 4px; }
  .empty { color: var(--vscode-descriptionForeground); font-style: italic; font-size: 12px; }
</style>
</head>
<body>
<h2>$(map) Team Workspace Map</h2>
<p style="font-size:11px;color:var(--vscode-descriptionForeground)">
  ${this._users.length} team member${this._users.length !== 1 ? "s" : ""} •
  ${online.length} online • ${away.length} away • ${offline.length} offline
</p>

${online.length > 0 ? `<div class="section">
  <div class="section-title">🟢 Online (${online.length})</div>
  ${online.map(renderUser).join("")}
</div>` : ""}

${away.length > 0 ? `<div class="section">
  <div class="section-title">🟡 Away (${away.length})</div>
  ${away.map(renderUser).join("")}
</div>` : ""}

${offline.length > 0 ? `<div class="section">
  <div class="section-title">⚫ Offline (${offline.length})</div>
  ${offline.map(renderUser).join("")}
</div>` : ""}

${this._users.length === 0 ? '<p class="empty">No team members connected.</p>' : ""}

<script>
  const vscode = acquireVsCodeApi();
</script>
</body>
</html>`;
  }

  dispose(): void {
    this._disposables.forEach((d) => d.dispose());
    this._disposables = [];
  }
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function shortFileName(path: string): string {
  return path.split(/[/\\]/).pop() ?? path;
}

function formatLastSeen(timestamp: number): string {
  const ageSec = Math.floor((Date.now() - timestamp) / 1000);
  if (ageSec < 30) return "Just now";
  if (ageSec < 60) return `${ageSec}s ago`;
  const ageMin = Math.floor(ageSec / 60);
  if (ageMin < 60) return `${ageMin}m ago`;
  return `${Math.floor(ageMin / 60)}h ago`;
}

// ── VSCode Command Registration ───────────────────────────────────────────────

export function registerWorkspaceMapCommands(
  ctx: vscode.ExtensionContext,
  getUsers: () => TeamHubUser[]
): void {
  ctx.subscriptions.push(
    vscode.commands.registerCommand(
      "teamHub.workspaceMap.show",
      () => {
        const panel = WorkspaceMapPanel.show(ctx);
        panel.updateUsers(getUsers());
      }
    )
  );
}
