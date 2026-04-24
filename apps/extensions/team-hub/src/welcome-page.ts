import * as vscode from 'vscode';
import { TeamHubActions } from './actions';

const escapeHtml = (value: string): string => value
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

export class TeamHubWelcomePage implements vscode.Disposable {
  private panel: vscode.WebviewPanel | undefined;
  private readonly welcomeKey = 'teamHub.welcomePageShown';

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly workspaceState: vscode.Memento,
    private readonly actions: TeamHubActions
  ) {}

  async openIfNeeded(): Promise<void> {
    if (!this.workspaceState.get<boolean>(this.welcomeKey, false)) {
      await this.open();
      await this.workspaceState.update(this.welcomeKey, true);
    }
  }

  async open(): Promise<void> {
    if (this.panel) {
      this.panel.reveal(vscode.ViewColumn.One);
      return;
    }

    this.panel = vscode.window.createWebviewPanel(
      'teamHubWelcome',
      'KC IDE Welcome',
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [this.extensionUri]
      }
    );

    this.panel.onDidDispose(() => {
      this.panel = undefined;
    });

    this.panel.webview.onDidReceiveMessage(async (message) => {
      switch (message.action) {
        case 'open-sidebar':
          await vscode.commands.executeCommand('workbench.view.extension.teamHub-container');
          break;
        case 'start-meet':
          await this.actions.startMeet();
          break;
        case 'share-workspace':
          await this.actions.shareWorkspace();
          break;
        case 'open-settings':
          this.actions.openSettings();
          break;
      }
    });

    this.panel.webview.html = this.renderHtml(this.panel.webview);
  }

  private renderHtml(webview: vscode.Webview): string {
    const nonce = `${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`;
    const cspSource = webview.cspSource;

    return `<!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${cspSource} https: data:; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <style>
            :root {
              color-scheme: dark;
            }

            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              padding: 32px;
              box-sizing: border-box;
              font-family: var(--vscode-font-family);
              color: var(--vscode-foreground);
              background:
                radial-gradient(circle at top left, rgba(92, 106, 196, 0.28), transparent 36%),
                radial-gradient(circle at bottom right, rgba(32, 178, 170, 0.18), transparent 28%),
                var(--vscode-editor-background);
            }

            .panel {
              width: min(920px, 100%);
              border: 1px solid var(--vscode-widget-border, rgba(255, 255, 255, 0.08));
              border-radius: 24px;
              background: linear-gradient(180deg, rgba(255, 255, 255, 0.04), rgba(255, 255, 255, 0.02));
              box-shadow: 0 24px 80px rgba(0, 0, 0, 0.32);
              overflow: hidden;
            }

            .hero {
              padding: 34px 34px 24px;
              display: grid;
              gap: 18px;
              border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            }

            .kicker {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              width: fit-content;
              padding: 6px 12px;
              border-radius: 999px;
              background: rgba(255, 255, 255, 0.08);
              font-size: 12px;
              letter-spacing: 0.08em;
              text-transform: uppercase;
            }

            h1 {
              margin: 0;
              font-size: clamp(2rem, 5vw, 3.8rem);
              line-height: 0.98;
              letter-spacing: -0.04em;
            }

            .subtitle {
              margin: 0;
              max-width: 60ch;
              font-size: 1.02rem;
              line-height: 1.55;
              opacity: 0.88;
            }

            .actions {
              display: flex;
              flex-wrap: wrap;
              gap: 12px;
            }

            button {
              appearance: none;
              border: 1px solid transparent;
              border-radius: 12px;
              padding: 11px 16px;
              font: inherit;
              cursor: pointer;
              transition: transform 120ms ease, background 120ms ease, border-color 120ms ease;
            }

            button:hover {
              transform: translateY(-1px);
            }

            .primary {
              background: var(--vscode-button-background);
              color: var(--vscode-button-foreground);
            }

            .secondary {
              background: transparent;
              color: var(--vscode-foreground);
              border-color: rgba(255, 255, 255, 0.14);
            }

            .grid {
              display: grid;
              grid-template-columns: repeat(3, minmax(0, 1fr));
              gap: 16px;
              padding: 24px 34px 34px;
            }

            .card {
              padding: 18px;
              border-radius: 18px;
              background: rgba(255, 255, 255, 0.04);
              border: 1px solid rgba(255, 255, 255, 0.08);
            }

            .card h2 {
              margin: 0 0 8px;
              font-size: 0.98rem;
            }

            .card p {
              margin: 0;
              line-height: 1.55;
              opacity: 0.84;
            }

            .footer {
              padding: 0 34px 30px;
              font-size: 0.88rem;
              opacity: 0.72;
            }

            @media (max-width: 720px) {
              .grid {
                grid-template-columns: 1fr;
              }

              .hero,
              .grid,
              .footer {
                padding-left: 20px;
                padding-right: 20px;
              }
            }
          </style>
        </head>
        <body>
          <main class="panel">
            <section class="hero">
              <div class="kicker">KC IDE · ElevatedIQ</div>
              <h1>Welcome to your on-prem engineering workspace.</h1>
              <p class="subtitle">KC IDE brings presence, collaboration, and shared workflows into one branded surface. Open the Team Hub sidebar, start a quick meet, or share the current workspace without leaving the editor.</p>
              <div class="actions">
                <button class="primary" data-action="open-sidebar">Open Team Hub</button>
                <button class="secondary" data-action="start-meet">Start Meet</button>
                <button class="secondary" data-action="share-workspace">Share Workspace</button>
                <button class="secondary" data-action="open-settings">Open Settings</button>
              </div>
            </section>

            <section class="grid">
              <article class="card">
                <h2>Real-time presence</h2>
                <p>See who is online, who is away, and which files are already being edited so you can avoid collisions.</p>
              </article>
              <article class="card">
                <h2>Same-file awareness</h2>
                <p>Keep work visible across the team without leaking infrastructure details or switching to another tool.</p>
              </article>
              <article class="card">
                <h2>Fast collaboration</h2>
                <p>Share a workspace link, start a Meet, or jump into settings with a single click from the welcome surface.</p>
              </article>
            </section>

            <div class="footer">Hosted on Kushnir.cloud infrastructure. Branded for KC IDE and ready for team collaboration.</div>
          </main>

          <script nonce="${nonce}">
            const vscode = acquireVsCodeApi();
            document.querySelectorAll('[data-action]').forEach((button) => {
              button.addEventListener('click', () => {
                const action = button.getAttribute('data-action');
                if (action) {
                  vscode.postMessage({ action });
                }
              });
            });
          </script>
        </body>
      </html>`;
  }

  dispose(): void {
    this.panel?.dispose();
    this.panel = undefined;
  }
}