import * as vscode from 'vscode';
import type { TeamHubConfig, TeamHubSnapshot, TeamHubStatusBarTileId } from './types';

export type TeamHubStatusBarTileSpec = {
  id: TeamHubStatusBarTileId;
  text: string;
  tooltip: string;
};

const TILE_ORDER: TeamHubStatusBarTileId[] = ['online', 'away', 'offline', 'same-file', 'workspace'];

function createTileSpec(id: TeamHubStatusBarTileId, snapshot: TeamHubSnapshot): TeamHubStatusBarTileSpec {
  const counts = snapshot.groupedUsers;
  const currentFile = snapshot.currentFile ?? snapshot.currentUser.currentFile ?? 'No active file';
  const currentWorkspace = snapshot.currentUser.workspace ?? 'Team Hub';

  switch (id) {
    case 'online':
      return {
        id,
        text: `$(organization) ${counts.online.length}`,
        tooltip: `${counts.online.length} collaborator${counts.online.length === 1 ? '' : 's'} online`,
      };
    case 'away':
      return {
        id,
        text: `$(clock) ${counts.away.length}`,
        tooltip: `${counts.away.length} collaborator${counts.away.length === 1 ? '' : 's'} away`,
      };
    case 'offline':
      return {
        id,
        text: `$(circle-slash) ${counts.offline.length}`,
        tooltip: `${counts.offline.length} collaborator${counts.offline.length === 1 ? '' : 's'} offline`,
      };
    case 'same-file':
      return {
        id,
        text: `$(files) ${snapshot.sameFileUsers.length}`,
        tooltip: `${snapshot.sameFileUsers.length} collaborator${snapshot.sameFileUsers.length === 1 ? '' : 's'} in ${currentFile}`,
      };
    case 'workspace':
      return {
        id,
        text: `$(workspace-trusted) ${currentWorkspace}`,
        tooltip: `Current workspace: ${currentWorkspace}`,
      };
  }
}

export function buildTeamHubStatusBarTileSpecs(snapshot: TeamHubSnapshot, config: TeamHubConfig): TeamHubStatusBarTileSpec[] {
  const requestedTiles = config.statusBarTiles.length > 0 ? config.statusBarTiles : ['online', 'same-file', 'workspace'];
  const uniqueTiles = [...new Set(requestedTiles)].filter((tile): tile is TeamHubStatusBarTileId => TILE_ORDER.includes(tile as TeamHubStatusBarTileId));

  return uniqueTiles.map((tileId) => createTileSpec(tileId, snapshot));
}

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
}import * as vscode from 'vscode';
import type { TeamHubConfig, TeamHubSnapshot, TeamHubStatusBarTileId } from './types';

export type TeamHubStatusBarTileSpec = {
  id: TeamHubStatusBarTileId;
  text: string;
  tooltip: string;
};

const TILE_ORDER: TeamHubStatusBarTileId[] = ['online', 'away', 'offline', 'same-file', 'workspace'];

function createTileSpec(id: TeamHubStatusBarTileId, snapshot: TeamHubSnapshot): TeamHubStatusBarTileSpec {
  const counts = snapshot.groupedUsers;
  const currentFile = snapshot.currentFile ?? snapshot.currentUser.currentFile ?? 'No active file';
  const currentWorkspace = snapshot.currentUser.workspace ?? 'Team Hub';

  switch (id) {
    case 'online':
      return {
        id,
        text: `$(organization) ${counts.online.length}`,
        tooltip: `${counts.online.length} collaborator${counts.online.length === 1 ? '' : 's'} online`,
      };
    case 'away':
      return {
        id,
        text: `$(clock) ${counts.away.length}`,
        tooltip: `${counts.away.length} collaborator${counts.away.length === 1 ? '' : 's'} away`,
      };
    case 'offline':
      return {
        id,
        text: `$(circle-slash) ${counts.offline.length}`,
        tooltip: `${counts.offline.length} collaborator${counts.offline.length === 1 ? '' : 's'} offline`,
      };
    case 'same-file':
      return {
        id,
        text: `$(files) ${snapshot.sameFileUsers.length}`,
        tooltip: `${snapshot.sameFileUsers.length} collaborator${snapshot.sameFileUsers.length === 1 ? '' : 's'} in ${currentFile}`,
      };
    case 'workspace':
      return {
        id,
        text: `$(workspace-trusted) ${currentWorkspace}`,
        tooltip: `Current workspace: ${currentWorkspace}`,
      };
  }
}

export function buildTeamHubStatusBarTileSpecs(snapshot: TeamHubSnapshot, config: TeamHubConfig): TeamHubStatusBarTileSpec[] {
  const requestedTiles = config.statusBarTiles.length > 0 ? config.statusBarTiles : ['online', 'same-file', 'workspace'];
  const uniqueTiles = [...new Set(requestedTiles)].filter((tile): tile is TeamHubStatusBarTileId => TILE_ORDER.includes(tile as TeamHubStatusBarTileId));

  return uniqueTiles.map((tileId) => createTileSpec(tileId, snapshot));
}

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