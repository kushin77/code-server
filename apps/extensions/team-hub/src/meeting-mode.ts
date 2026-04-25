// @file        apps/extensions/team-hub/src/meeting-mode.ts
// @module      collab/meeting-mode
// @description Meeting mode — focus indicator + automatic DND during calls
// @governance  GOV-002: IaC, immutable, idempotent
// Issue #1091: [Collab-2.8] Meeting mode - focus indicator + automatic DND during calls

import * as vscode from "vscode";

export type MeetingState = "inactive" | "active" | "presenting";

export interface MeetingSession {
  title: string;
  state: MeetingState;
  startedAt: number;
  durationMinutes?: number;  // Optional scheduled duration
  notificationsBlocked: boolean;
}

export class MeetingModeManager {
  private _session: MeetingSession | null = null;
  private _statusBarItem: vscode.StatusBarItem;
  private _dndTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly _onStateChange = new vscode.EventEmitter<MeetingSession | null>();
  readonly onStateChange = this._onStateChange.event;

  constructor(
    private readonly presenceSidecarUrl: string,
    private readonly currentUserId: string
  ) {
    this._statusBarItem = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Left,
      95
    );
    this._statusBarItem.command = "teamHub.meeting.toggle";
    this._statusBarItem.hide();
  }

  get isActive(): boolean {
    return this._session !== null;
  }

  get session(): MeetingSession | null {
    return this._session ? { ...this._session } : null;
  }

  // ── Start meeting mode ────────────────────────────────────────────────────

  async startMeeting(options?: {
    title?: string;
    durationMinutes?: number;
    presenting?: boolean;
  }): Promise<void> {
    const title =
      options?.title ||
      (await vscode.window.showInputBox({
        prompt: "Meeting title (optional)",
        placeHolder: "e.g. Sprint Review, 1:1, Code Review",
        value: "Meeting",
      })) ||
      "Meeting";

    this._session = {
      title,
      state: options?.presenting ? "presenting" : "active",
      startedAt: Date.now(),
      durationMinutes: options?.durationMinutes,
      notificationsBlocked: true,
    };

    // Update status bar
    this._updateStatusBar();
    this._statusBarItem.show();

    // Auto-end timer if duration provided
    if (options?.durationMinutes) {
      this._dndTimer = setTimeout(
        () => this.endMeeting(),
        options.durationMinutes * 60 * 1000
      );
    }

    // Broadcast presence update
    await this._broadcastMeetingState();
    this._onStateChange.fire(this._session);

    vscode.window.showInformationMessage(
      `Meeting mode active: "${title}". Notifications muted.`,
      "End Meeting"
    ).then((choice) => {
      if (choice === "End Meeting") this.endMeeting();
    });
  }

  // ── End meeting mode ──────────────────────────────────────────────────────

  async endMeeting(): Promise<void> {
    if (!this._session) return;

    const duration = Math.floor((Date.now() - this._session.startedAt) / 60000);
    const title = this._session.title;

    this._session = null;
    if (this._dndTimer) {
      clearTimeout(this._dndTimer);
      this._dndTimer = null;
    }

    this._statusBarItem.hide();
    await this._broadcastMeetingState();
    this._onStateChange.fire(null);

    vscode.window.showInformationMessage(
      `Meeting "${title}" ended (${duration} min). Notifications restored.`
    );
  }

  // ── Toggle presenting state ───────────────────────────────────────────────

  async togglePresenting(): Promise<void> {
    if (!this._session) return;
    this._session.state =
      this._session.state === "presenting" ? "active" : "presenting";
    this._updateStatusBar();
    await this._broadcastMeetingState();
    this._onStateChange.fire(this._session);
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  private _updateStatusBar(): void {
    if (!this._session) return;
    const icon =
      this._session.state === "presenting" ? "$(broadcast)" : "$(call-incoming)";
    const label = this._session.state === "presenting"
      ? `${icon} Presenting`
      : `${icon} In Meeting`;
    this._statusBarItem.text = label;
    this._statusBarItem.tooltip = [
      `Meeting: ${this._session.title}`,
      `Duration: ${Math.floor((Date.now() - this._session.startedAt) / 60000)}m`,
      `DND: ${this._session.notificationsBlocked ? "On" : "Off"}`,
      "Click to end meeting",
    ].join("\n");
    this._statusBarItem.backgroundColor = new vscode.ThemeColor(
      this._session.state === "presenting"
        ? "statusBarItem.errorBackground"
        : "statusBarItem.warningBackground"
    );
  }

  // ── Broadcast to presence sidecar ────────────────────────────────────────

  private async _broadcastMeetingState(): Promise<void> {
    if (!this.presenceSidecarUrl) return;
    try {
      await fetch(`${this.presenceSidecarUrl}/presence`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          userId: this.currentUserId,
          meetingMode: this._session
            ? {
                active: true,
                title: this._session.title,
                state: this._session.state,
                dnd: this._session.notificationsBlocked,
              }
            : { active: false },
        }),
        signal: AbortSignal.timeout(3000),
      });
    } catch {
      // Non-critical
    }
  }

  dispose(): void {
    if (this._dndTimer) clearTimeout(this._dndTimer);
    this._statusBarItem.dispose();
    this._onStateChange.dispose();
  }
}

// ── VSCode Command Registration ───────────────────────────────────────────────

export function registerMeetingModeCommands(
  ctx: vscode.ExtensionContext,
  manager: MeetingModeManager
): void {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("teamHub.meeting.toggle", async () => {
      if (manager.isActive) {
        await manager.endMeeting();
      } else {
        await manager.startMeeting();
      }
    }),

    vscode.commands.registerCommand("teamHub.meeting.start", async () => {
      await manager.startMeeting();
    }),

    vscode.commands.registerCommand("teamHub.meeting.startPresenting", async () => {
      if (manager.isActive) {
        await manager.togglePresenting();
      } else {
        await manager.startMeeting({ presenting: true });
      }
    }),

    vscode.commands.registerCommand("teamHub.meeting.end", async () => {
      await manager.endMeeting();
    })
  );
}
