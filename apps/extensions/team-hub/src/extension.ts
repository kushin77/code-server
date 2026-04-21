import * as vscode from 'vscode';
import { readTeamHubConfig } from './config';
import { PresenceService } from './presence';
import { TeamHubActions } from './actions';
import { TeamHubSidebarProvider } from './sidebar';
import { TeamHubStatusBarManager } from './status-bar';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const getConfig = readTeamHubConfig;
  const presenceService = new PresenceService(getConfig);
  const actions = new TeamHubActions(presenceService);
  const sidebarProvider = new TeamHubSidebarProvider(context.extensionUri, presenceService, actions, getConfig);
  const statusBarManager = new TeamHubStatusBarManager(getConfig, 'teamHub.openSidebar');

  const syncStatusBar = (): void => {
    statusBarManager.update(presenceService.getSnapshot());
  };

  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('teamHub.sidebar', sidebarProvider),
    vscode.commands.registerCommand('teamHub.openSidebar', async () => {
      await vscode.commands.executeCommand('workbench.view.extension.teamHub-container');
    }),
    vscode.commands.registerCommand('teamHub.mentionUser', (userId: string) => actions.mentionUser(userId)),
    vscode.commands.registerCommand('teamHub.startMeet', (userIds: string[] | undefined) => actions.startMeet(userIds ?? [])),
    vscode.commands.registerCommand('teamHub.goToUserFile', (userId: string) => actions.goToUserFile(userId)),
    vscode.commands.registerCommand('teamHub.refreshPresence', () => actions.refreshPresence()),
    vscode.commands.registerCommand('teamHub.settings', () => actions.openSettings()),
    vscode.commands.registerCommand('teamHub.shareWorkspace', () => actions.shareWorkspace()),
    statusBarManager,
    new vscode.Disposable(() => presenceService.dispose())
  );

  context.subscriptions.push(
    presenceService.onDidChangeSnapshot(() => {
      syncStatusBar();
    })
  );

  const config = getConfig();
  if (config.enableAutoPresence) {
    context.subscriptions.push(
      vscode.window.onDidChangeActiveTextEditor((editor) => {
        presenceService.updateActiveEditor(editor);
      })
    );
  }

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('teamHub')) {
        syncStatusBar();
      }
    })
  );

  await presenceService.connect();
  presenceService.updateActiveEditor(vscode.window.activeTextEditor);
  syncStatusBar();
}

export function deactivate(): void {
  // VS Code disposes subscriptions on shutdown.
}
