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
        tooltip: `${counts.online.length} collaborator${counts.online.length === 1 ? '' : 's'} online`
      };
    case 'away':
      return {
        id,
        text: `$(clock) ${counts.away.length}`,
        tooltip: `${counts.away.length} collaborator${counts.away.length === 1 ? '' : 's'} away`
      };
    case 'offline':
      return {
        id,
        text: `$(circle-slash) ${counts.offline.length}`,
        tooltip: `${counts.offline.length} collaborator${counts.offline.length === 1 ? '' : 's'} offline`
      };
    case 'same-file':
      return {
        id,
        text: `$(files) ${snapshot.sameFileUsers.length}`,
        tooltip: `${snapshot.sameFileUsers.length} collaborator${snapshot.sameFileUsers.length === 1 ? '' : 's'} in ${currentFile}`
      };
    case 'workspace':
      return {
        id,
        text: `$(workspace-trusted) ${currentWorkspace}`,
        tooltip: `Current workspace: ${currentWorkspace}`
      };
  }
}

export function buildTeamHubStatusBarTileSpecs(snapshot: TeamHubSnapshot, config: TeamHubConfig): TeamHubStatusBarTileSpec[] {
  const requestedTiles = config.statusBarTiles.length > 0 ? config.statusBarTiles : ['online', 'same-file', 'workspace'];
  const uniqueTiles = [...new Set(requestedTiles)].filter((tile): tile is TeamHubStatusBarTileId => TILE_ORDER.includes(tile as TeamHubStatusBarTileId));

  return uniqueTiles.map((tileId) => createTileSpec(tileId, snapshot));
}