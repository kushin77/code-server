/**
 * Code Server Copilot Memory + GitHub Integration Extension
 * Provides UI panels, commands, and configuration for the self-cleaning copilot
 * 
 * Installation:
 * 1. Copy this extension to ~/.local/share/code-server/extensions/ (or via marketplace)
 * 2. Reload Code Server
 * 3. Set API keys in settings: copilot-memory.anthropicApiKey, copilot-memory.githubToken
 * 4. Open "Copilot Memory" view in activity bar
 */

import * as vscode from "vscode";
import { CopilotMemoryEngine } from "./engines/memory-engine";
import { GitHubScannerService } from "./engines/github-scanner";
import { ChatWebviewProvider } from "./webviews/chat-webview";
import { MemoryStateProvider } from "./webviews/memory-state-webview";
import { GitHubStatusProvider } from "./webviews/github-status-webview";

let context: vscode.ExtensionContext;
let memoryEngine: CopilotMemoryEngine;
let githubScanner: GitHubScannerService;
let chatProvider: ChatWebviewProvider;
let statusBar: vscode.StatusBarItem;

export async function activate(ctx: vscode.ExtensionContext) {
  context = ctx;

  console.log("🤖 Copilot Memory + GitHub Extension activating...");

  // Initialize memory engine
  const config = vscode.workspace.getConfiguration("copilot-memory");
  const apiKey = config.get<string>("anthropicApiKey") || process.env.ANTHROPIC_API_KEY;
  const githubToken = config.get<string>("githubToken") || process.env.GITHUB_TOKEN;
  const githubOrg = config.get<string>("githubOrg") || process.env.GITHUB_ORG;
  const memoryBackend = config.get<string>("memoryBackend") || "memory";

  if (!apiKey) {
    vscode.window.showErrorMessage(
      "Copilot Memory: Anthropic API key not set. Go to Settings > copilot-memory.anthropicApiKey"
    );
    return;
  }

  // Initialize engines
  memoryEngine = new CopilotMemoryEngine(apiKey, memoryBackend, context.globalStorageUri.fsPath);
  githubScanner = new GitHubScannerService(githubToken, githubOrg);

  // Register webview providers
  chatProvider = new ChatWebviewProvider(context.extensionUri, memoryEngine, githubScanner);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      "copilot-memory.chat",
      chatProvider,
      { webviewOptions: { retainContextWhenHidden: true } }
    )
  );

  const memoryStateProvider = new MemoryStateProvider(context.extensionUri, memoryEngine);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      "copilot-memory.memoryState",
      memoryStateProvider,
      { webviewOptions: { retainContextWhenHidden: true } }
    )
  );

  const githubStatusProvider = new GitHubStatusProvider(
    context.extensionUri,
    memoryEngine,
    githubScanner
  );
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      "copilot-memory.githubStatus",
      githubStatusProvider,
      { webviewOptions: { retainContextWhenHidden: true } }
    )
  );

  // Register commands
  registerCommands();

  // Create status bar item
  statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusBar.command = "copilot-memory.startChat";
  updateStatusBar();
  context.subscriptions.push(statusBar);

  // Listen for config changes
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("copilot-memory")) {
        console.log("⚙️ Copilot Memory config changed, reloading...");
        // Reload engines if needed
      }
    })
  );

  console.log("✓ Copilot Memory Extension activated");
}

function registerCommands() {
  // Start chat
  context.subscriptions.push(
    vscode.commands.registerCommand("copilot-memory.startChat", async () => {
      vscode.commands.executeCommand("workbench.view.extension.copilot-memory-view");
    })
  );

  // Scan GitHub
  context.subscriptions.push(
    vscode.commands.registerCommand("copilot-memory.scanGitHub", async () => {
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: "Scanning GitHub..." },
        async (progress) => {
          try {
            progress.report({ increment: 0 });
            await githubScanner.scanAndImport(memoryEngine);
            progress.report({ increment: 100 });
            vscode.window.showInformationMessage("✓ GitHub scan complete. Memory updated.");
            updateStatusBar();
          } catch (error) {
            vscode.window.showErrorMessage(`GitHub scan failed: ${error.message}`);
          }
        }
      );
    })
  );

  // Show memory state
  context.subscriptions.push(
    vscode.commands.registerCommand("copilot-memory.showMemoryState", async () => {
      const memory = await memoryEngine.exportMemoryContext();
      const doc = await vscode.workspace.openUntitledDocument({
        language: "json",
        content: JSON.stringify(memory, null, 2),
      });
      await vscode.window.showTextDocument(doc);
    })
  );

  // Export memory
  context.subscriptions.push(
    vscode.commands.registerCommand("copilot-memory.exportMemory", async () => {
      const uri = await vscode.window.showSaveDialog({
        filters: { JSON: ["json"] },
        defaultUri: vscode.Uri.file("copilot-memory-export.json"),
      });

      if (uri) {
        const memory = await memoryEngine.exportMemoryContext();
        const bytes = Buffer.from(JSON.stringify(memory, null, 2));
        await vscode.workspace.fs.writeFile(uri, bytes);
        vscode.window.showInformationMessage(`Memory exported to ${uri.fsPath}`);
      }
    })
  );

  // Import memory
  context.subscriptions.push(
    vscode.commands.registerCommand("copilot-memory.importMemory", async () => {
      const uris = await vscode.window.showOpenDialog({
        filters: { JSON: ["json"] },
      });

      if (uris && uris.length > 0) {
        const bytes = await vscode.workspace.fs.readFile(uris[0]);
        const data = JSON.parse(bytes.toString());
        await memoryEngine.importMemoryContext(data);
        vscode.window.showInformationMessage("Memory imported successfully.");
        updateStatusBar();
      }
    })
  );

  // Clear memory
  context.subscriptions.push(
    vscode.commands.registerCommand("copilot-memory.clearMemory", async () => {
      const confirmed = await vscode.window.showWarningMessage(
        "Clear all copilot memory? This cannot be undone.",
        "Clear",
        "Cancel"
      );

      if (confirmed === "Clear") {
        await memoryEngine.clearMemory();
        vscode.window.showInformationMessage("Memory cleared.");
        updateStatusBar();
      }
    })
  );
}

async function updateStatusBar() {
  try {
    const memory = await memoryEngine.exportMemoryContext();
    const activeGoals = (memory.active_goals || []).length;
    const completedGoals = (memory.completed_goals || []).length;
    statusBar.text = `$(comment) Copilot: ${activeGoals} active, ${completedGoals} done`;
    statusBar.show();
  } catch (error) {
    statusBar.text = "$(comment) Copilot";
    statusBar.show();
  }
}

export function deactivate() {
  console.log("Copilot Memory Extension deactivating...");
  // Cleanup
}

// ============================================================================
// MEMORY ENGINE (Abstracted for sharing)
// ============================================================================

export class CopilotMemoryEngine {
  private backend: "memory" | "redis" | "postgresql";
  private storageUri: string;
  private memory: any;
  private apiKey: string;

  constructor(apiKey: string, backend: string, storageUri: string) {
    this.apiKey = apiKey;
    this.backend = backend as "memory" | "redis" | "postgresql";
    this.storageUri = storageUri;
    this.memory = {
      session_goals: [],
      active_context: { current_domain: null, current_task: null, blockers: [], assumptions: [] },
      contradiction_log: [],
    };
  }

  async chat(userMessage: string, domain?: string): Promise<string> {
    // Call Claude Sonnet 4 with memory context injected
    const Anthropic = require("@anthropic-ai/sdk");
    const client = new Anthropic({ apiKey: this.apiKey });

    const memoryContext = JSON.stringify(this.memory, null, 2);
    const systemPrompt = `You are an autonomous enterprise copilot with memory.
    
[SESSION MEMORY]
${memoryContext}

CORE MANDATE:
1. Never repeat yourself. If you've suggested this before, flag it.
2. Expose conflicts. If contradicting a prior decision, ask first.
3. Lock decisions. Once committed, align future advice with it.
4. Assume nothing. State assumptions upfront.
5. Use GitHub context when available.`;

    const response = await client.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2000,
      temperature: 0.7,
      system: systemPrompt,
      messages: [{ role: "user", content: userMessage }],
    });

    const message = response.content[0].type === "text" ? response.content[0].text : "";

    // Record in memory
    await this.recordSuggestion(message, domain || "general");

    return message;
  }

  async recordSuggestion(content: string, domain: string): Promise<void> {
    // Add to memory (implementation depends on backend)
    this.memory.session_goals.push({
      id: `goal_${Date.now()}`,
      domain,
      intent: content.slice(0, 100),
      status: "suggested",
      created_at: new Date().toISOString(),
    });
  }

  async exportMemoryContext(): Promise<any> {
    return {
      active_goals: this.memory.session_goals.filter((g: any) => g.status === "active"),
      completed_goals: this.memory.session_goals.filter((g: any) => g.status === "completed"),
      contradictions: this.memory.contradiction_log,
      timestamp: new Date().toISOString(),
    };
  }

  async importMemoryContext(data: any): Promise<void> {
    this.memory = data;
  }

  async clearMemory(): Promise<void> {
    this.memory = {
      session_goals: [],
      active_context: {
        current_domain: null,
        current_task: null,
        blockers: [],
        assumptions: [],
      },
      contradiction_log: [],
    };
  }
}

// ============================================================================
// GITHUB SCANNER SERVICE (Shareable)
// ============================================================================

export class GitHubScannerService {
  private token: string;
  private org: string;

  constructor(token: string, org: string) {
    this.token = token;
    this.org = org;
  }

  async scanAndImport(memoryEngine: CopilotMemoryEngine): Promise<void> {
    // Implement GitHub scanning logic (see previous artifact)
    // For brevity, stubbed here
    console.log(`Scanning GitHub org: ${this.org}`);
    // Call GitHub GraphQL API, synthesize goals, import into memory
  }

  async getRepoStats(): Promise<any> {
    // Return stats for GitHub status view
    return {
      repos: 0,
      issues: 0,
      prs: 0,
      lastScan: null,
    };
  }
}

// ============================================================================
// WEBVIEW PROVIDERS (UI for Code Server activity bar)
// ============================================================================

export class ChatWebviewProvider implements vscode.WebviewViewProvider {
  constructor(
    private extensionUri: vscode.Uri,
    private memoryEngine: CopilotMemoryEngine,
    private githubScanner: GitHubScannerService
  ) {}

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    webviewView.webview.options = { enableScripts: true };
    webviewView.webview.html = this.getHtmlForWebview(webviewView.webview);

    webviewView.webview.onDidReceiveMessage((message) => {
      if (message.command === "sendMessage") {
        this.handleChatMessage(message.text, webviewView);
      }
    });
  }

  private async handleChatMessage(userMessage: string, webviewView: vscode.WebviewView): Promise<void> {
    try {
      const response = await this.memoryEngine.chat(userMessage);
      webviewView.webview.postMessage({ command: "copilotResponse", text: response });
    } catch (error) {
      webviewView.webview.postMessage({ command: "error", text: error.message });
    }
  }

  private getHtmlForWebview(webview: vscode.Webview): string {
    return `<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; padding: 12px; }
    .chat-history { height: 400px; overflow-y: auto; border: 1px solid #ccc; padding: 8px; margin-bottom: 8px; }
    .message { margin: 4px 0; padding: 4px; border-radius: 4px; }
    .user { background: #e3f2fd; }
    .copilot { background: #f5f5f5; }
    .input-group { display: flex; gap: 4px; }
    input { flex: 1; padding: 4px; border: 1px solid #ccc; }
    button { padding: 4px 8px; }
  </style>
</head>
<body>
  <h3>💬 Copilot Chat</h3>
  <div class="chat-history" id="history"></div>
  <div class="input-group">
    <input type="text" id="input" placeholder="Ask copilot..." />
    <button onclick="sendMessage()">Send</button>
  </div>
  <script>
    const vscode = acquireVsCodeApi();
    function sendMessage() {
      const input = document.getElementById("input");
      const text = input.value.trim();
      if (!text) return;
      addMessage("user", text);
      vscode.postMessage({ command: "sendMessage", text });
      input.value = "";
    }
    function addMessage(role, text) {
      const history = document.getElementById("history");
      const msg = document.createElement("div");
      msg.className = "message " + role;
      msg.textContent = text;
      history.appendChild(msg);
      history.scrollTop = history.scrollHeight;
    }
    window.addEventListener("message", (e) => {
      if (e.data.command === "copilotResponse") {
        addMessage("copilot", e.data.text);
      }
    });
  </script>
</body>
</html>`;
  }
}

export class MemoryStateProvider implements vscode.WebviewViewProvider {
  constructor(private extensionUri: vscode.Uri, private memoryEngine: CopilotMemoryEngine) {}

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    webviewView.webview.options = { enableScripts: true };
    webviewView.webview.html = `
      <h3>📋 Memory State</h3>
      <p>Active goals, decisions, and blockers will appear here.</p>
    `;
  }
}

export class GitHubStatusProvider implements vscode.WebviewViewProvider {
  constructor(
    private extensionUri: vscode.Uri,
    private memoryEngine: CopilotMemoryEngine,
    private githubScanner: GitHubScannerService
  ) {}

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    webviewView.webview.options = { enableScripts: true };
    webviewView.webview.html = `
      <h3>🐙 GitHub Status</h3>
      <p>Repos, issues, and PRs from your GitHub scan will appear here.</p>
      <button onclick="vscode.postMessage({ command: 'scan' })">Scan Now</button>
    `;
  }
}
