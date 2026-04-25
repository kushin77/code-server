// @file        apps/extensions/team-hub/src/shared-clipboard.ts
// @module      collab/shared-clipboard
// @description Shared clipboard with cross-user paste history
// @governance  GOV-002: IaC, immutable, idempotent
// Issue #1080: [Collab-1.8] Shared clipboard with cross-user paste history

import * as vscode from "vscode";

const MAX_HISTORY_ITEMS = 50;
const CLIPBOARD_CHANNEL = "team-hub:clipboard";

export interface ClipboardEntry {
  id: string;
  content: string;
  contentPreview: string;      // First 80 chars for display
  authorId: string;
  authorName: string;
  timestamp: number;
  language?: string;            // Detected language for syntax highlighting
  sourceFile?: string;          // File the content was copied from
  sourceLine?: number;
}

export class SharedClipboardManager {
  private readonly _history: ClipboardEntry[] = [];
  private readonly _onHistoryChange = new vscode.EventEmitter<ClipboardEntry[]>();
  readonly onHistoryChange = this._onHistoryChange.event;

  constructor(
    private readonly presenceSidecarUrl: string,
    private readonly currentUserId: string,
    private readonly currentUserName: string
  ) {}

  // ── Record a copy event from the current user ───────────────────────────

  async recordCopy(content: string, context?: {
    language?: string;
    sourceFile?: string;
    sourceLine?: number;
  }): Promise<ClipboardEntry> {
    const entry: ClipboardEntry = {
      id: `clip-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      content,
      contentPreview: content.length > 80
        ? content.slice(0, 77) + "..."
        : content,
      authorId: this.currentUserId,
      authorName: this.currentUserName,
      timestamp: Date.now(),
      language: context?.language,
      sourceFile: context?.sourceFile,
      sourceLine: context?.sourceLine,
    };

    this._addToHistory(entry);
    await this._broadcastEntry(entry);
    return entry;
  }

  // ── Receive a clipboard entry from a remote user ────────────────────────

  receiveRemoteEntry(entry: ClipboardEntry): void {
    this._addToHistory(entry);
  }

  // ── Paste from history ───────────────────────────────────────────────────

  async pasteFromHistory(): Promise<void> {
    if (this._history.length === 0) {
      vscode.window.showInformationMessage("Shared clipboard history is empty.");
      return;
    }

    const items = this._history
      .slice()
      .reverse()  // Most recent first
      .map((entry) => ({
        label: entry.contentPreview,
        description: `${entry.authorName} • ${this._formatAge(entry.timestamp)}`,
        detail: entry.sourceFile
          ? `From: ${entry.sourceFile}:${entry.sourceLine ?? ""}`
          : undefined,
        entry,
      }));

    const selected = await vscode.window.showQuickPick(items, {
      title: "Shared Clipboard History",
      placeHolder: "Select an entry to paste",
      matchOnDescription: true,
      matchOnDetail: true,
    });

    if (!selected) return;

    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      // Copy to native clipboard if no editor open
      await vscode.env.clipboard.writeText(selected.entry.content);
      vscode.window.showInformationMessage(
        "Copied to clipboard (no active editor)."
      );
      return;
    }

    await editor.edit((editBuilder) => {
      for (const selection of editor.selections) {
        editBuilder.replace(selection, selected.entry.content);
      }
    });
  }

  getHistory(): ClipboardEntry[] {
    return [...this._history];
  }

  clearHistory(): void {
    this._history.length = 0;
    this._onHistoryChange.fire([]);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  private _addToHistory(entry: ClipboardEntry): void {
    // Dedup: skip if identical content already at top of history
    if (
      this._history.length > 0 &&
      this._history[this._history.length - 1].content === entry.content
    ) {
      return;
    }

    this._history.push(entry);
    if (this._history.length > MAX_HISTORY_ITEMS) {
      this._history.shift();
    }
    this._onHistoryChange.fire([...this._history]);
  }

  private async _broadcastEntry(entry: ClipboardEntry): Promise<void> {
    if (!this.presenceSidecarUrl) return;
    try {
      await fetch(`${this.presenceSidecarUrl}/clipboard`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(entry),
        signal: AbortSignal.timeout(3000),
      });
    } catch {
      // Non-critical — clipboard sharing works locally even if broadcast fails
    }
  }

  private _formatAge(timestamp: number): string {
    const ageMs = Date.now() - timestamp;
    const ageSec = Math.floor(ageMs / 1000);
    if (ageSec < 60) return `${ageSec}s ago`;
    const ageMin = Math.floor(ageSec / 60);
    if (ageMin < 60) return `${ageMin}m ago`;
    const ageHr = Math.floor(ageMin / 60);
    return `${ageHr}h ago`;
  }

  dispose(): void {
    this._onHistoryChange.dispose();
    this._history.length = 0;
  }
}

// ── VSCode Command Registration ───────────────────────────────────────────────

export function registerSharedClipboardCommands(
  ctx: vscode.ExtensionContext,
  manager: SharedClipboardManager
): void {
  ctx.subscriptions.push(
    // Record copy with context
    vscode.commands.registerCommand(
      "teamHub.clipboard.copyToShared",
      async () => {
        const editor = vscode.window.activeTextEditor;
        const content = await vscode.env.clipboard.readText();
        if (!content) {
          vscode.window.showWarningMessage("Clipboard is empty.");
          return;
        }
        await manager.recordCopy(content, {
          language: editor?.document.languageId,
          sourceFile: editor?.document.uri.fsPath,
          sourceLine: editor?.selection.start.line,
        });
        vscode.window.showInformationMessage(
          "Shared with team clipboard."
        );
      }
    ),

    // Show paste history
    vscode.commands.registerCommand(
      "teamHub.clipboard.showHistory",
      async () => manager.pasteFromHistory()
    ),

    // Clear history
    vscode.commands.registerCommand(
      "teamHub.clipboard.clearHistory",
      () => {
        manager.clearHistory();
        vscode.window.showInformationMessage("Clipboard history cleared.");
      }
    )
  );
}
