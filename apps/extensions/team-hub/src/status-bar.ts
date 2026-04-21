import * as vscode from 'vscode';
import type { TeamHubConfig, TeamHubSnapshot, TeamHubStatusBarTileId } from './types';
import { buildTeamHubStatusBarTileSpecs } from './status-bar-specs';

export class TeamHubStatusBarManager implements vscode.Disposable {
  private readonly items = new Map<TeamHubStatusBarTileId, vscode.StatusBarItem>();

  constructor(
    private readonly getConfig: () => TeamHubConfig,
    private readonly openSidebarCommandId: string,
  ) {}

  update(snapshot: TeamHubSnapshot): void {
    const config = this.getConfig();
    const specs = buildTeamHubStatusBarTileSpecs(snapshot, config);
    const activeTileIds = new Set(specs.map((spec) => spec.id));

    for (const [tileId, item] of this.items.entries()) {
      if (!activeTileIds.has(tileId)) {
        item.hide();
      }
    }

    for (const [index, spec] of specs.entries()) {
      const item = this.items.get(spec.id) ?? vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100 - index);
      item.text = spec.text;
      item.tooltip = spec.tooltip;
      item.command = this.openSidebarCommandId;
      item.show();
      this.items.set(spec.id, item);
    }
  }

  dispose(): void {
    for (const item of this.items.values()) {
      item.dispose();
    }
    this.items.clear();
  }
}