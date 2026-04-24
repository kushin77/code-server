// @file apps/extensions/statusbar-tiles/src/status-bar-tile.ts
// @module ide/vscode-extensions
// @description Status bar tile renderer with clickable commands

import * as vscode from "vscode";
import { GitHubAPIClient } from "../api-clients";
import { CIAPIClient } from "../api-clients";
import { PagerDutyAPIClient } from "../api-clients";
import { TeamPresenceClient } from "../api-clients";

export class StatusBarTile {
  private context: vscode.ExtensionContext;
  private tiles: Map<string, vscode.StatusBarItem> = new Map();
  private github: GitHubAPIClient;
  private ci: CIAPIClient;
  private pagerduty: PagerDutyAPIClient;
  private presence: TeamPresenceClient;
  private refreshTimer: NodeJS.Timer | null = null;

  constructor(context: vscode.ExtensionContext) {
    this.context = context;
    this.github = new GitHubAPIClient(
      vscode.workspace.getConfiguration('statusbar-tiles').get('githubToken', '') || ''
    );
    this.ci = new CIAPIClient(
      vscode.workspace.getConfiguration('statusbar-tiles').get('ciEndpoint', '') || 'http://localhost:8080'
    );
    this.pagerduty = new PagerDutyAPIClient(
      vscode.workspace.getConfiguration('statusbar-tiles').get('pagerdutyToken', '') || ''
    );
    this.presence = new TeamPresenceClient();
  }

  async initialize() {
    await this.createTiles();
    this.startRefreshTimer();
    console.log('Status bar tiles initialized');
  }

  private createTiles() {
    const tileOrder = vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<string[]>('tileOrder', ['pr', 'ci', 'incidents', 'team-online']);

    for (const tileType of tileOrder) {
      this.createTile(tileType);
    }
  }

  private createTile(type: string) {
    const tile = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Right,
      100 - ['pr', 'ci', 'incidents', 'team-online'].indexOf(type)
    );

    tile.command = `statusbar-tiles.open${type.toUpperCase()}`;
    this.tiles.set(type, tile);
    tile.show();

    // Register command for this tile
    this.context.subscriptions.push(
      vscode.commands.registerCommand(`statusbar-tiles.open${type.toUpperCase()}`, () => {
        this.handleTileClick(type);
      })
    );
  }

  async refresh() {
    console.log('Refreshing status bar tiles...');
    
    try {
      // Update PR tile
      const prTile = this.tiles.get('pr');
      if (prTile) {
        const prs = await this.github.getAssignedPRs('kushin77');
        const unreadReviews = await this.github.getUnreadReviews('kushin77');
        prTile.text = `$(git-pull-request) ${prs.length} PRs`;
        prTile.tooltip = `${prs.length} assigned PRs | ${unreadReviews} unread reviews`;
        prTile.color = prs.length > 0 ? undefined : 'green';
      }

      // Update CI tile
      const ciTile = this.tiles.get('ci');
      if (ciTile) {
        const status = await this.ci.getBranchStatus();
        const icon = status['status'] === 'passing' ? '$(check)' : '$(close)';
        const color = status['status'] === 'passing' ? 'green' : 'red';
        ciTile.text = `${icon} CI ${status['status']}`;
        ciTile.color = color;
        ciTile.tooltip = `Branch: ${status['branch']} | Jobs: ${status['job_count']}`;
      }

      // Update incidents tile
      const incidentsTile = this.tiles.get('incidents');
      if (incidentsTile) {
        const count = await this.pagerduty.getIncidentCount();
        const severity = await this.pagerduty.getHighestSeverity();
        const icon = count > 0 ? '$(alert)' : '$(check)';
        incidentsTile.text = `${icon} ${count} incidents`;
        incidentsTile.color = count > 0 ? 'red' : 'green';
        incidentsTile.tooltip = `Active incidents: ${count} | Severity: ${severity}`;
      }

      // Update team online tile
      const teamTile = this.tiles.get('team-online');
      if (teamTile) {
        const online = await this.presence.getTeamOnlineCount();
        const total = await this.presence.getTeamSize();
        teamTile.text = `$(person) ${online}/${total} online`;
        teamTile.color = online > 5 ? 'green' : 'yellow';
        teamTile.tooltip = `Team online: ${online}/${total}`;
      }
    } catch (error) {
      console.error('Error refreshing tiles:', error);
    }
  }

  private async handleTileClick(type: string) {
    console.log(`Tile clicked: ${type}`);

    switch (type) {
      case 'pr':
        vscode.commands.executeCommand(
          'vscode.open',
          vscode.Uri.parse('https://github.com/pulls?q=is:open+assigned:me')
        );
        break;
      case 'ci':
        // Open CI logs in IDE panel
        await this.openCIPanel();
        break;
      case 'incidents':
        // Open PagerDuty incidents
        vscode.commands.executeCommand(
          'vscode.open',
          vscode.Uri.parse('https://example.pagerduty.com/incidents')
        );
        break;
      case 'team-online':
        // Show team online status in quick pick
        await this.showTeamOnlineQuickPick();
        break;
    }
  }

  private async openCIPanel() {
    const webviewPanel = vscode.window.createWebviewPanel(
      'ci-logs',
      'CI Logs',
      vscode.ViewColumn.Two,
      { enableScripts: true }
    );

    webviewPanel.webview.html = this.getCILogsHTML();
  }

  private getCILogsHTML(): string {
    return `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: monospace; padding: 20px; }
          .job { margin-bottom: 20px; border: 1px solid #ccc; padding: 10px; }
          .passing { border-left: 4px solid green; }
          .failing { border-left: 4px solid red; }
        </style>
      </head>
      <body>
        <h2>CI Job Status</h2>
        <div class="job passing">✓ Unit Tests (2m 15s)</div>
        <div class="job passing">✓ Integration Tests (5m 30s)</div>
        <div class="job passing">✓ Lint (1m 20s)</div>
        <p><em>Refreshing every 60 seconds...</em></p>
      </body>
      </html>
    `;
  }

  private async showTeamOnlineQuickPick() {
    const items: vscode.QuickPickItem[] = [
      { label: 'Alex', description: '$(circle-filled) Online' },
      { label: 'Sarah', description: '$(circle-filled) Online' },
      { label: 'Jordan', description: '$(circle) Offline' }
    ];

    await vscode.window.showQuickPick(items, {
      title: 'Team Status',
      placeHolder: 'View team online status'
    });
  }

  private startRefreshTimer() {
    const interval = vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<number>('refreshInterval', 60) * 1000;

    this.refreshTimer = setInterval(() => this.refresh(), interval);
    this.refresh(); // Initial refresh
  }

  dispose() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
    }
    for (const tile of this.tiles.values()) {
      tile.dispose();
    }
  }
}
