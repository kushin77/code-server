// @file        apps/extensions/team-hub/src/session-cost-tracker.ts
// @module      collab/cost
// @description Session cost tracking per user and project for chargeback
// @governance  GOV-002: IaC, immutable, idempotent
// Issue #1118: [Collab-5.5] Session cost tracking per user and project for chargeback

import * as vscode from "vscode";

export interface SessionCostConfig {
  ratePerHourUsd: number;     // Billing rate per workspace-hour
  currency: string;           // Default: "USD"
  billingPeriodDays: number;  // Default: 30 (monthly)
}

export interface SessionRecord {
  sessionId: string;
  userId: string;
  projectId: string;
  startTime: number;
  endTime?: number;
  durationMs: number;
  costUsd: number;
  metadata: {
    cpuRequest?: string;
    memoryRequest?: string;
    gpuRequest?: string;
  };
}

const DEFAULT_CONFIG: SessionCostConfig = {
  ratePerHourUsd: 0.15,    // $0.15/hr default
  currency: "USD",
  billingPeriodDays: 30,
};

export class SessionCostTracker {
  private _currentSessionId: string | null = null;
  private _sessionStart: number | null = null;
  private _records: SessionRecord[] = [];
  private _statusBarItem: vscode.StatusBarItem;

  constructor(
    private readonly config: SessionCostConfig = DEFAULT_CONFIG,
    private readonly presenceSidecarUrl: string,
    private readonly userId: string,
    private readonly projectId: string
  ) {
    this._statusBarItem = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Right,
      90
    );
    this._statusBarItem.command = "teamHub.cost.showReport";
  }

  // ── Start a billable session ─────────────────────────────────────────────

  startSession(metadata?: SessionRecord["metadata"]): void {
    if (this._currentSessionId) return; // Already tracking

    this._currentSessionId = `sess-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    this._sessionStart = Date.now();

    this._updateStatusBar();
    this._statusBarItem.show();

    this._startStatusBarTimer();
  }

  // ── End a billable session ────────────────────────────────────────────────

  async endSession(): Promise<SessionRecord | null> {
    if (!this._currentSessionId || !this._sessionStart) return null;

    const durationMs = Date.now() - this._sessionStart;
    const durationHrs = durationMs / (1000 * 60 * 60);
    const costUsd = parseFloat((durationHrs * this.config.ratePerHourUsd).toFixed(4));

    const record: SessionRecord = {
      sessionId: this._currentSessionId,
      userId: this.userId,
      projectId: this.projectId,
      startTime: this._sessionStart,
      endTime: Date.now(),
      durationMs,
      costUsd,
      metadata: {},
    };

    this._records.push(record);
    this._currentSessionId = null;
    this._sessionStart = null;

    this._statusBarItem.hide();
    await this._reportSession(record);

    return record;
  }

  // ── Current session cost (live) ───────────────────────────────────────────

  get currentCostUsd(): number {
    if (!this._sessionStart) return 0;
    const durationHrs = (Date.now() - this._sessionStart) / (1000 * 60 * 60);
    return parseFloat((durationHrs * this.config.ratePerHourUsd).toFixed(4));
  }

  get currentDurationMs(): number {
    if (!this._sessionStart) return 0;
    return Date.now() - this._sessionStart;
  }

  // ── Billing period report ──────────────────────────────────────────────────

  getBillingReport(
    periodDays: number = this.config.billingPeriodDays
  ): {
    totalCostUsd: number;
    totalDurationMs: number;
    sessionCount: number;
    records: SessionRecord[];
    byProject: Record<string, { costUsd: number; durationMs: number }>;
  } {
    const cutoff = Date.now() - periodDays * 24 * 60 * 60 * 1000;
    const relevant = this._records.filter(
      (r) => r.startTime >= cutoff
    );

    const byProject: Record<string, { costUsd: number; durationMs: number }> = {};
    let totalCostUsd = 0;
    let totalDurationMs = 0;

    for (const record of relevant) {
      totalCostUsd += record.costUsd;
      totalDurationMs += record.durationMs;
      if (!byProject[record.projectId]) {
        byProject[record.projectId] = { costUsd: 0, durationMs: 0 };
      }
      byProject[record.projectId].costUsd += record.costUsd;
      byProject[record.projectId].durationMs += record.durationMs;
    }

    return {
      totalCostUsd: parseFloat(totalCostUsd.toFixed(4)),
      totalDurationMs,
      sessionCount: relevant.length,
      records: relevant,
      byProject,
    };
  }

  // ── Status bar update ─────────────────────────────────────────────────────

  private _timerHandle: ReturnType<typeof setInterval> | null = null;

  private _startStatusBarTimer(): void {
    this._timerHandle = setInterval(() => {
      this._updateStatusBar();
    }, 60_000); // Update every minute
  }

  private _updateStatusBar(): void {
    const cost = this.currentCostUsd;
    const durationMin = Math.floor(this.currentDurationMs / 60000);
    this._statusBarItem.text = `$(clock) ${durationMin}m $${cost.toFixed(3)}`;
    this._statusBarItem.tooltip = [
      `Session Cost Tracker`,
      `Duration: ${durationMin}m`,
      `Cost: $${cost.toFixed(4)} (@ $${this.config.ratePerHourUsd}/hr)`,
      `Project: ${this.projectId}`,
      "Click for billing report",
    ].join("\n");
  }

  // ── Report to backend ─────────────────────────────────────────────────────

  private async _reportSession(record: SessionRecord): Promise<void> {
    if (!this.presenceSidecarUrl) return;
    try {
      await fetch(`${this.presenceSidecarUrl}/sessions/cost`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(record),
        signal: AbortSignal.timeout(5000),
      });
    } catch {
      // Non-critical — local records are the source of truth
    }
  }

  dispose(): void {
    if (this._timerHandle) clearInterval(this._timerHandle);
    this._statusBarItem.dispose();
  }
}

// ── VSCode Command Registration ───────────────────────────────────────────────

export function registerSessionCostCommands(
  ctx: vscode.ExtensionContext,
  tracker: SessionCostTracker
): void {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("teamHub.cost.showReport", async () => {
      const report = tracker.getBillingReport();
      const durationHrs = (report.totalDurationMs / (1000 * 60 * 60)).toFixed(1);

      const message = [
        `💰 Session Cost Report (30 days)`,
        `Total: $${report.totalCostUsd.toFixed(2)} (${durationHrs}h, ${report.sessionCount} sessions)`,
        ...Object.entries(report.byProject).map(([proj, data]) => {
          const hrs = (data.durationMs / (1000 * 60 * 60)).toFixed(1);
          return `  ${proj}: $${data.costUsd.toFixed(2)} (${hrs}h)`;
        }),
      ].join("\n");

      await vscode.window.showInformationMessage(message, { modal: true }, "OK");
    }),

    vscode.commands.registerCommand("teamHub.cost.exportCsv", async () => {
      const report = tracker.getBillingReport();
      const rows = [
        "session_id,user_id,project_id,start_time,end_time,duration_hours,cost_usd",
        ...report.records.map((r) => [
          r.sessionId,
          r.userId,
          r.projectId,
          new Date(r.startTime).toISOString(),
          r.endTime ? new Date(r.endTime).toISOString() : "",
          (r.durationMs / (1000 * 60 * 60)).toFixed(4),
          r.costUsd.toFixed(4),
        ].join(","))
      ].join("\n");

      const uri = await vscode.window.showSaveDialog({
        defaultUri: vscode.Uri.file("session-costs.csv"),
        filters: { "CSV Files": ["csv"] },
      });
      if (uri) {
        await vscode.workspace.fs.writeFile(
          uri,
          Buffer.from(rows, "utf-8")
        );
        vscode.window.showInformationMessage(
          `Saved ${report.records.length} session records to ${uri.fsPath}`
        );
      }
    })
  );
}
