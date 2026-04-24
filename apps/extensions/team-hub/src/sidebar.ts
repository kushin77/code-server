import * as vscode from 'vscode';
import { PresenceService } from './presence';
import { TeamHubActions } from './actions';
import { renderTeamHubWebviewHtml } from './webview';
import type { TeamHubConfig, TeamHubSnapshot } from './types';
import { createActivityEntry, prependActivityEntry, type TeamHubActivityEntry } from './activity-feed';
import { resolveTeamHubCommand } from './command-interface';
import { applyUserIsolation, TEAM_HUB_PRIVATE_VIEW_KEY } from './user-isolation';

export class TeamHubSidebarProvider implements vscode.WebviewViewProvider {
  private view: vscode.WebviewView | undefined;
  private lastSnapshot: TeamHubSnapshot | undefined;
  private activityEntries: TeamHubActivityEntry[] = [
    createActivityEntry('system', 'KC IDE Team Hub ready', 'Activity feed initialized for this workspace')
  ];

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly presenceService: PresenceService,
    private readonly actions: TeamHubActions,
    private readonly getConfig: () => TeamHubConfig,
    private readonly workspaceState: vscode.Memento
  ) {
    this.isolationEnabled = this.workspaceState.get<boolean>(TEAM_HUB_PRIVATE_VIEW_KEY, false);

    this.presenceService.onDidChangeSnapshot((snapshot) => {
      this.lastSnapshot = snapshot;
      this.render();
    });
  }

  private isolationEnabled: boolean;

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    this.view = webviewView;
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    };

    webviewView.webview.onDidReceiveMessage(async (message) => {
      switch (message.action) {
        case 'mention':
          if (typeof message.userId === 'string') {
            const user = this.presenceService.findUser(message.userId);
            await this.actions.mentionUser(message.userId);
            if (user) {
              this.recordActivity('collaboration', 'Mention copied', `Prepared @mention for ${user.displayName}`);
            }
          }
          break;
        case 'start-meet':
          await this.actions.startMeet();
          this.recordActivity('collaboration', 'Meet link copied', 'Copied a Google Meet link to the clipboard');
          break;
        case 'share-workspace':
          await this.actions.shareWorkspace();
          this.recordActivity('collaboration', 'Workspace link copied', 'Copied the current workspace share link');
          break;
        case 'focus-file':
          if (typeof message.userId === 'string') {
            const user = this.presenceService.findUser(message.userId);
            await this.actions.goToUserFile(message.userId);
            if (user) {
              this.recordActivity('navigation', 'Opened collaborator file', `Jumped to ${user.displayName}'s active file`);
            }
          }
          break;
        case 'refresh':
          await this.actions.refreshPresence();
          this.recordActivity('presence', 'Presence refreshed', 'Pulled the latest collaboration snapshot');
          break;
        case 'settings':
          this.actions.openSettings();
          this.recordActivity('settings', 'Settings opened', 'Focused Team Hub settings');
          break;
        case 'run-command':
          if (typeof message.commandText === 'string') {
            await this.runCommand(message.commandText);
          }
          break;
        case 'toggle-isolation':
          await this.toggleIsolation();
          break;
      }
    });

    this.render();
  }

  private render(): void {
    if (!this.view) {
      return;
    }

    const snapshot = applyUserIsolation(this.lastSnapshot ?? this.presenceService.getSnapshot(), this.isolationEnabled);
    this.view.webview.html = renderTeamHubWebviewHtml(snapshot, this.getConfig(), this.view.webview, this.activityEntries, this.isolationEnabled);
  }

  private recordActivity(kind: TeamHubActivityEntry['kind'], title: string, detail?: string): void {
    this.activityEntries = prependActivityEntry(
      this.activityEntries,
      createActivityEntry(kind, title, detail)
    );
    this.render();
  }

  private async runCommand(commandText: string): Promise<void> {
    const command = resolveTeamHubCommand(commandText);

    if (!command) {
      vscode.window.showInformationMessage(`Unknown KC IDE command: ${commandText}`);
      return;
    }

    switch (command.action) {
      case 'open-sidebar':
        await vscode.commands.executeCommand('workbench.view.extension.teamHub-container');
        break;
      case 'start-meet':
        await this.actions.startMeet();
        break;
      case 'share-workspace':
        await this.actions.shareWorkspace();
        break;
      case 'refresh-presence':
        await this.actions.refreshPresence();
        break;
      case 'open-settings':
        this.actions.openSettings();
        break;
    }

    this.recordActivity('system', command.description, commandText.trim());
  }

  private async toggleIsolation(): Promise<void> {
    this.isolationEnabled = !this.isolationEnabled;
    await this.workspaceState.update(TEAM_HUB_PRIVATE_VIEW_KEY, this.isolationEnabled);

    this.recordActivity(
      'settings',
      this.isolationEnabled ? 'Private view enabled' : 'Private view disabled',
      this.isolationEnabled ? 'Hidden collaborator data in this workspace' : 'Restored shared collaboration view'
    );
  }
}
