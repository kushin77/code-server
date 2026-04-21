// @file        apps/frontend/src/extensions/ticket-linking-extension.ts
// @module      integrations/ticket-linking
// @description VS Code extension entry point for ticket linking integration
// @owner       collab-9
// @status      active

import * as vscode from 'vscode';
import TicketLinkingPanel from './ticket-linking-panel';

let detector: any;
let ticketPanel: TicketLinkingPanel | undefined;

/**
 * VS Code extension activation
 */
export async function activate(context: vscode.ExtensionContext): Promise<void> {
  console.log('Ticket Linking Extension activated');

  // Lazy load detector service
  const { default: TicketDetector } = await import(
    '../../../backend/src/services/ticket-linking/ticket-detector'
  );

  // Initialize detector with API credentials from workspace settings
  const config = vscode.workspace.getConfiguration('ticketLinking');
  const apiCredentials = new Map([
    ['linear', config.get<string>('linearApiKey') || process.env.LINEAR_API_KEY || ''],
    ['jira', config.get<string>('jiraApiKey') || process.env.JIRA_API_KEY || ''],
    ['github', config.get<string>('githubToken') || process.env.GITHUB_TOKEN || ''],
  ]);

  detector = new TicketDetector(apiCredentials);

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('ticketLinking.showPanel', () => {
      ticketPanel = TicketLinkingPanel.createOrShow(context.extensionUri);
      refreshTickets();
    }),

    vscode.commands.registerCommand('ticketLinking.refresh', async () => {
      await refreshTickets();
    }),

    vscode.commands.registerCommand('ticketLinking.configure', async () => {
      await configureCredentials();
    })
  );

  // Auto-show panel when opening a file with tickets
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(async (editor) => {
      if (editor && detector) {
        const tickets = await detector.getResolvedTicketsForFile(
          editor.document.uri.fsPath,
          editor.document.getText()
        );

        if (tickets.length > 0) {
          if (!ticketPanel) {
            ticketPanel = TicketLinkingPanel.createOrShow(context.extensionUri);
          }
          ticketPanel.updateTickets(tickets);
        }
      }
    })
  );

  // Refresh on document change (debounced)
  let changeTimer: NodeJS.Timeout;
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument(async (event) => {
      clearTimeout(changeTimer);
      changeTimer = setTimeout(async () => {
        await refreshTickets();
      }, 500); // Debounce 500ms
    })
  );

  // Add context menu item
  context.subscriptions.push(
    vscode.commands.registerCommand('ticketLinking.linkTicket', async (args) => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showErrorMessage('No editor active');
        return;
      }

      const ticketId = await vscode.window.showInputBox({
        prompt: 'Enter ticket ID (e.g., PROJ-123, #456)',
        validateInput: (value) => {
          if (!value) return 'Ticket ID cannot be empty';
          return null;
        },
      });

      if (ticketId) {
        // Insert ticket reference at cursor
        const edit = new vscode.WorkspaceEdit();
        edit.insert(editor.document.uri, editor.selection.active, `/* Relates to: ${ticketId} */`);
        await vscode.workspace.applyEdit(edit);

        // Refresh to resolve the new ticket
        await refreshTickets();
      }
    })
  );

  // Status bar item
  const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right);
  statusBar.command = 'ticketLinking.showPanel';
  statusBar.text = '📋 Tickets';
  statusBar.show();
  context.subscriptions.push(statusBar);

  // Clean up expired cache periodically
  setInterval(() => {
    if (detector) {
      detector.clearExpiredCache();
    }
  }, 600000); // Every 10 minutes
}

/**
 * Refresh detected tickets in the active editor
 */
async function refreshTickets(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || !detector) return;

  try {
    const tickets = await detector.getResolvedTicketsForFile(
      editor.document.uri.fsPath,
      editor.document.getText()
    );

    if (ticketPanel) {
      ticketPanel.updateTickets(tickets);
    }

    // Update status bar
    const statusBar = vscode.window.statusBarItems.find(
      (item) => item.text === '📋 Tickets'
    );
    if (statusBar && tickets.length > 0) {
      statusBar.text = `📋 ${tickets.length} Ticket${tickets.length !== 1 ? 's' : ''}`;
    }
  } catch (error) {
    console.error('Error refreshing tickets:', error);
  }
}

/**
 * Configure API credentials
 */
async function configureCredentials(): Promise<void> {
  const selected = await vscode.window.showQuickPick(
    ['Linear', 'Jira', 'GitHub', 'Cancel'],
    {
      placeHolder: 'Select ticket system to configure',
    }
  );

  if (!selected || selected === 'Cancel') return;

  const systemName = selected.toLowerCase();
  const keyName = `${systemName}ApiKey`;

  const apiKey = await vscode.window.showInputBox({
    prompt: `Enter ${selected} API Key (stored in workspace settings)`,
    password: true,
    validateInput: (value) => {
      if (!value) return `${selected} API Key cannot be empty`;
      return null;
    },
  });

  if (apiKey) {
    const config = vscode.workspace.getConfiguration('ticketLinking');
    await config.update(keyName, apiKey, vscode.ConfigurationTarget.Workspace);

    // Reinitialize detector with new credentials
    const newCredentials = new Map([
      ['linear', config.get<string>('linearApiKey') || ''],
      ['jira', config.get<string>('jiraApiKey') || ''],
      ['github', config.get<string>('githubToken') || ''],
    ]);
    const { default: TicketDetector } = await import(
      '../../../backend/src/services/ticket-linking/ticket-detector'
    );
    detector = new TicketDetector(newCredentials);

    vscode.window.showInformationMessage(`${selected} credentials configured`);
    await refreshTickets();
  }
}

/**
 * Extension deactivation
 */
export function deactivate(): void {
  if (ticketPanel) {
    ticketPanel.dispose();
  }
}

export { TicketLinkingPanel };
