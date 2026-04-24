import * as vscode from 'vscode';
import { buildMentionText, buildMeetLink, buildWorkspaceShareLink } from './collaboration-utils';
export class TeamHubActions {
    constructor(presenceService) {
        this.presenceService = presenceService;
    }
    async mentionUser(userId) {
        const user = this.presenceService.findUser(userId);
        if (!user) {
            vscode.window.showWarningMessage(`No Team Hub user found for ${userId}`);
            return;
        }
        const mention = buildMentionText(user);
        await vscode.env.clipboard.writeText(mention);
        vscode.window.showInformationMessage(`Copied mention for ${user.displayName}`);
    }
    async startMeet(userIds = []) {
        const users = userIds.length > 0 ? this.presenceService.findUsers(userIds) : this.presenceService.getSnapshot().sameFileUsers;
        const link = buildMeetLink(users);
        await vscode.env.clipboard.writeText(link);
        vscode.window.showInformationMessage('Copied Google Meet link to clipboard');
    }
    async goToUserFile(userId) {
        const user = this.presenceService.findUser(userId);
        if (!user?.currentFile) {
            vscode.window.showWarningMessage(`No active file recorded for ${user?.displayName ?? userId}`);
            return;
        }
        const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri;
        const targetUri = workspaceRoot ? vscode.Uri.joinPath(workspaceRoot, user.currentFile) : vscode.Uri.file(user.currentFile);
        try {
            const document = await vscode.workspace.openTextDocument(targetUri);
            await vscode.window.showTextDocument(document, { preview: false });
        }
        catch {
            vscode.window.showInformationMessage(`File is not available locally: ${user.currentFile}`);
        }
    }
    async refreshPresence() {
        await this.presenceService.refresh();
        return this.presenceService.getSnapshot();
    }
    async shareWorkspace() {
        const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.toString() ?? 'vscode://workbench';
        const workspaceLink = buildWorkspaceShareLink(workspaceRoot, this.presenceService.getCurrentFile());
        await vscode.env.clipboard.writeText(workspaceLink);
        vscode.window.showInformationMessage('Workspace link copied to clipboard');
    }
    openSettings() {
        void vscode.commands.executeCommand('workbench.action.openSettings', 'teamHub');
    }
}
//# sourceMappingURL=actions.js.map