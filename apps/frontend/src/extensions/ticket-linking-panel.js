// @file        apps/frontend/src/extensions/ticket-linking-panel.ts
// @module      integrations/ticket-linking
// @description VS Code extension side panel for displaying linked tickets with context
// @owner       collab-9
// @status      active
import * as vscode from 'vscode';
/**
 * Ticket Linking Panel - Side panel UI for VS Code showing detected tickets
 */
export class TicketLinkingPanel {
    constructor(panel, extensionUri) {
        this.panel = panel;
        this.extensionUri = extensionUri;
        this.panel.onDidDispose(() => this.dispose(), null);
        this.panel.webview.onDidReceiveMessage(async (message) => {
            await this.handleMessage(message);
        }, null);
        this.update();
    }
    static createOrShow(extensionUri) {
        const column = vscode.ViewColumn.Beside;
        if (TicketLinkingPanel.currentPanel) {
            TicketLinkingPanel.currentPanel.panel.reveal(column);
            return TicketLinkingPanel.currentPanel;
        }
        const panel = vscode.window.createWebviewPanel('ticketLinking', 'Linked Tickets', column, {
            enableScripts: true,
            enableForms: true,
            localResourceRoots: [
                vscode.Uri.joinPath(extensionUri, 'media'),
                vscode.Uri.joinPath(extensionUri, 'dist'),
            ],
        });
        TicketLinkingPanel.currentPanel = new TicketLinkingPanel(panel, extensionUri);
        return TicketLinkingPanel.currentPanel;
    }
    dispose() {
        TicketLinkingPanel.currentPanel = undefined;
        this.panel.dispose();
    }
    update() {
        this.panel.webview.html = this.getHtmlContent();
    }
    getHtmlContent() {
        return `
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Linked Tickets</title>
        <style>
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }

          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--vscode-editor-background);
            color: var(--vscode-editor-foreground);
            padding: 12px;
          }

          .header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 16px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--vscode-editorGroup-border);
          }

          .header-title {
            font-size: 14px;
            font-weight: 600;
            flex: 1;
          }

          .refresh-btn {
            padding: 4px 8px;
            background: var(--vscode-button-background);
            color: var(--vscode-button-foreground);
            border: none;
            border-radius: 2px;
            cursor: pointer;
            font-size: 12px;
          }

          .refresh-btn:hover {
            background: var(--vscode-button-hoverBackground);
          }

          .tickets-container {
            display: flex;
            flex-direction: column;
            gap: 8px;
          }

          .ticket-card {
            padding: 10px;
            background: var(--vscode-editorWidget-background);
            border: 1px solid var(--vscode-editorWidget-border);
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.2s;
          }

          .ticket-card:hover {
            background: var(--vscode-list-hoverBackground);
            border-color: var(--vscode-focusBorder);
          }

          .ticket-id {
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 12px;
            font-weight: 600;
            color: var(--vscode-symbolIcon-methodForeground);
          }

          .ticket-title {
            font-size: 13px;
            margin-top: 4px;
            line-height: 1.4;
          }

          .ticket-meta {
            display: flex;
            gap: 8px;
            margin-top: 6px;
            font-size: 11px;
            color: var(--vscode-descriptionForeground);
          }

          .badge {
            padding: 2px 6px;
            background: var(--vscode-editorGroupHeader-tabsBackground);
            border-radius: 2px;
            font-size: 10px;
          }

          .status {
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 10px;
            font-weight: 500;
          }

          .status.open {
            background: rgba(40, 167, 69, 0.2);
            color: #28a745;
          }

          .status.in-progress {
            background: rgba(255, 193, 7, 0.2);
            color: #ffc107;
          }

          .status.done {
            background: rgba(23, 162, 184, 0.2);
            color: #17a2b8;
          }

          .empty-state {
            text-align: center;
            padding: 24px 12px;
            color: var(--vscode-descriptionForeground);
          }

          .empty-state-icon {
            font-size: 32px;
            margin-bottom: 8px;
          }

          .context-section {
            margin-top: 12px;
            padding-top: 12px;
            border-top: 1px solid var(--vscode-editorGroup-border);
            font-size: 12px;
          }

          .context-label {
            font-weight: 600;
            color: var(--vscode-descriptionForeground);
            margin-bottom: 4px;
          }

          .context-code {
            background: var(--vscode-editor-background);
            padding: 4px;
            border-radius: 2px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 11px;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-all;
          }

          .loading {
            text-align: center;
            padding: 12px;
            color: var(--vscode-descriptionForeground);
          }

          .spinner {
            display: inline-block;
            animation: spin 1s linear infinite;
          }

          @keyframes spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
          }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="header-title">📋 Linked Tickets</div>
          <button class="refresh-btn" id="refreshBtn">↻ Refresh</button>
        </div>

        <div id="content">
          <div class="empty-state">
            <div class="empty-state-icon">📝</div>
            <div>No tickets detected in current file</div>
          </div>
        </div>

        <script>
          const vscode = acquireVsCodeApi();
          const content = document.getElementById('content');
          const refreshBtn = document.getElementById('refreshBtn');

          refreshBtn.addEventListener('click', () => {
            vscode.postMessage({ command: 'refresh' });
          });

          // Listen for tickets from extension
          window.addEventListener('message', (event) => {
            const message = event.data;

            if (message.command === 'updateTickets') {
              const tickets = message.tickets;

              if (!tickets || tickets.length === 0) {
                content.innerHTML = \`
                  <div class="empty-state">
                    <div class="empty-state-icon">📝</div>
                    <div>No tickets detected in current file</div>
                  </div>
                \`;
                return;
              }

              content.innerHTML = \`
                <div class="tickets-container">
                  \${tickets.map((ticket) => \`
                    <div class="ticket-card" data-url="\${ticket.url}">
                      <div class="ticket-id">\${ticket.id}</div>
                      <div class="ticket-title">\${ticket.title}</div>
                      <div class="ticket-meta">
                        <span class="status \${ticket.status.toLowerCase()}">\${ticket.status}</span>
                        \${ticket.assignee ? \`<span class="badge">@\${ticket.assignee}</span>\` : ''}
                        \${ticket.priority ? \`<span class="badge">\${ticket.priority}</span>\` : ''}
                      </div>
                      \${ticket.context ? \`
                        <div class="context-section">
                          <div class="context-label">📍 Found in: \${ticket.context.functionName || 'global scope'}</div>
                          <div class="context-code">\${ticket.context.currentLine}</div>
                        </div>
                      \` : ''}
                    </div>
                  \`).join('')}
                </div>
              \`;

              // Add click handlers
              document.querySelectorAll('.ticket-card').forEach((card) => {
                card.addEventListener('click', () => {
                  const url = card.dataset.url;
                  vscode.postMessage({ command: 'openTicket', url });
                });
              });
            }
          });

          // Request initial tickets
          vscode.postMessage({ command: 'getTickets' });
        </script>
      </body>
      </html>
    `;
    }
    async handleMessage(message) {
        switch (message.command) {
            case 'refresh':
                this.update();
                vscode.commands.executeCommand('ticketLinking.refresh');
                break;
            case 'openTicket':
                if (message.url) {
                    vscode.env.openExternal(vscode.Uri.parse(message.url));
                }
                break;
        }
    }
    updateTickets(tickets) {
        this.panel.webview.postMessage({
            command: 'updateTickets',
            tickets,
        });
    }
}
export default TicketLinkingPanel;
//# sourceMappingURL=ticket-linking-panel.js.map