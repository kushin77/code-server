// Team Hub Extension - Main Entry Point
// Implements VS Code sidebar for real-time team collaboration
// Features: presence awareness, file tracking, quick actions
import * as vscode from 'vscode';
import { PresenceService } from './services/presence';
import { MatrixService } from './services/matrix';
import { SidebarProvider } from './ui/sidebar';
import { CommandHandler } from './handlers/commands';
export async function activate(context) {
    console.log('Team Hub extension activated');
    // Initialize services
    const presenceService = new PresenceService();
    const matrixService = new MatrixService();
    // Register sidebar provider
    const sidebarProvider = new SidebarProvider(context.extensionUri, presenceService, matrixService);
    context.subscriptions.push(vscode.window.registerWebviewViewProvider('teamHub.sidebar', sidebarProvider));
    // Register commands
    const commandHandler = new CommandHandler(presenceService, matrixService);
    context.subscriptions.push(vscode.commands.registerCommand('teamHub.mentionUser', (userId) => commandHandler.mentionUser(userId)), vscode.commands.registerCommand('teamHub.startMeet', (userIds) => commandHandler.startMeet(userIds)), vscode.commands.registerCommand('teamHub.goToUserFile', (userId) => commandHandler.goToUserFile(userId)), vscode.commands.registerCommand('teamHub.refreshPresence', () => commandHandler.refreshPresence()), vscode.commands.registerCommand('teamHub.settings', () => vscode.commands.executeCommand('workbench.action.openSettings', 'teamHub')));
    // Subscribe to editor changes for auto-presence updates
    const activeEditorChangeSubscription = vscode.window.onDidChangeActiveTextEditor(async (editor) => {
        if (editor) {
            const fileName = editor.document.fileName;
            const language = editor.document.languageId;
            await presenceService.updatePresence({
                status: 'editing',
                fileName,
                language,
                timestamp: Date.now()
            });
        }
    });
    context.subscriptions.push(activeEditorChangeSubscription);
    // Start background services
    await presenceService.connect();
    await matrixService.connect();
    // Refresh presence every 5 seconds (configurable)
    const refreshInterval = setInterval(() => presenceService.broadcastPresence(), vscode.workspace.getConfiguration('teamHub').get('presenceUpdateInterval', 5000));
    context.subscriptions.push(new vscode.Disposable(() => clearInterval(refreshInterval)));
}
export function deactivate() {
    console.log('Team Hub extension deactivated');
}
//# sourceMappingURL=TEAM-HUB-EXTENSION-extension.js.map