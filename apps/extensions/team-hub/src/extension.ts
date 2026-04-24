import * as vscode from 'vscode';
import { CollaborationDetector } from './collaboration-detector';
import { ConflictResolver } from './conflict-resolver';
import { TeamCommunicationEngine } from './team-communication-engine';
import { WorkspaceFolderManager } from './workspace-folder-manager';
import { GitHubAccountManager } from './github-account-manager';
import { GitHubOAuthHandler } from './github-oauth-handler';
import { CopilotContextEngine } from './copilot-context-engine';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const collaborationDetector = new CollaborationDetector();
  const conflictResolver = new ConflictResolver();
  const communicationEngine = new TeamCommunicationEngine();
  const workspaceFolderManager = new WorkspaceFolderManager();
  const accountManager = new GitHubAccountManager();
  const oauthHandler = new GitHubOAuthHandler({
    clientId: process.env.GITHUB_CLIENT_ID || 'team-hub',
    clientSecret: process.env.GITHUB_CLIENT_SECRET || 'team-hub',
    redirectUri: 'https://localhost/team-hub/github/callback',
    scopes: ['read:user', 'repo']
  });
  const contextEngine = new CopilotContextEngine();

  context.subscriptions.push(
    vscode.commands.registerCommand('teamHub.openActivityFeed', async () => {
      await vscode.commands.executeCommand('workbench.view.extension.teamHub-container');
    }),
    vscode.commands.registerCommand('teamHub.openWelcome', async () => {
      vscode.window.showInformationMessage('KC IDE Team Hub is active.');
    }),
    vscode.commands.registerCommand('teamHub.mentionUser', async (userId: string) => {
      collaborationDetector.registerUserPresence(userId, userId);
      await communicationEngine.ensureChannel('team-hub');
      vscode.window.showInformationMessage(`Mentioned user ${userId}`);
    }),
    vscode.commands.registerCommand('teamHub.startMeet', async (userIds: string[] | undefined) => {
      await communicationEngine.startMeeting('Team Hub Meet', 'local-user', userIds ?? []);
      vscode.window.showInformationMessage('Started Team Hub meeting.');
    }),
    vscode.commands.registerCommand('teamHub.goToUserFile', async (userId: string) => {
      vscode.window.showInformationMessage(`Navigate to file for ${userId}`);
    }),
    vscode.commands.registerCommand('teamHub.refreshPresence', async () => {
      vscode.window.showInformationMessage('Presence refreshed.');
    }),
    vscode.commands.registerCommand('teamHub.settings', async () => {
      await vscode.commands.executeCommand('workbench.action.openSettings', 'teamHub');
    }),
    vscode.commands.registerCommand('teamHub.shareWorkspace', async () => {
      await workspaceFolderManager.saveWorkspaceConfig('team-hub-workspace.json');
      vscode.window.showInformationMessage('Workspace configuration captured.');
    }),
    vscode.commands.registerCommand('teamHub.resolveConflict', async () => {
      const conflicts = collaborationDetector.getDetectedConflicts();
      if (conflicts.length === 0) {
        vscode.window.showInformationMessage('No conflicts detected.');
        return;
      }

      const suggestions = await conflictResolver.generateMergeSuggestions(conflicts[0]);
      if (suggestions.length > 0) {
        await conflictResolver.applySuggestion(suggestions[0]);
      }
    }),
    vscode.commands.registerCommand('teamHub.authenticateGitHub', async () => {
      await oauthHandler.initiateOAuthFlow();
    }),
    vscode.commands.registerCommand('teamHub.buildContext', async (query: string) => {
      const result = await contextEngine.buildContext(query);
      vscode.window.showInformationMessage(
        `Context built from ${result.sources.docs.length} docs and ${result.sources.issues.length} issues.`
      );
    }),
    new vscode.Disposable(() => {
      accountManager.getAllAccounts();
    })
  );
}

export function deactivate(): void {
  // VS Code disposes subscriptions on shutdown.
}
