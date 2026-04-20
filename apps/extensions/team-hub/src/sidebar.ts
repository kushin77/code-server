import * as vscode from 'vscode';
import { PresenceService } from './presence';
import { TeamHubActions } from './actions';
import { renderTeamHubWebviewHtml } from './webview';
import type { TeamHubConfig, TeamHubSnapshot } from './types';

export class TeamHubSidebarProvider implements vscode.WebviewViewProvider {
  private view: vscode.WebviewView | undefined;
  private lastSnapshot: TeamHubSnapshot | undefined;

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly presenceService: PresenceService,
    private readonly actions: TeamHubActions,
    private readonly getConfig: () => TeamHubConfig
  ) {
    this.presenceService.onDidChangeSnapshot((snapshot) => {
      this.lastSnapshot = snapshot;
      this.render();
    });
  }

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
            await this.actions.mentionUser(message.userId);
          }
          break;
        case 'start-meet':
          await this.actions.startMeet();
          break;
        case 'share-workspace':
          await this.actions.shareWorkspace();
          break;
        case 'focus-file':
          if (typeof message.userId === 'string') {
            await this.actions.goToUserFile(message.userId);
          }
          break;
        case 'refresh':
          await this.actions.refreshPresence();
          break;
        case 'settings':
          this.actions.openSettings();
          break;
      }
    });

    this.render();
  }

  private render(): void {
    if (!this.view) {
      return;
    }

    const snapshot = this.lastSnapshot ?? this.presenceService.getSnapshot();
    this.view.webview.html = renderTeamHubWebviewHtml(snapshot, this.getConfig(), this.view.webview);
  }
}
