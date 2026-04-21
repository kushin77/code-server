import { describe, expect, it } from 'vitest';
import { buildTeamHubStatusBarTileSpecs } from '../src/status-bar-specs';
import type { TeamHubConfig, TeamHubSnapshot } from '../src/types';

const config: TeamHubConfig = {
  matrixHomeserver: '',
  roomId: '',
  presenceSidecarUrl: '',
  enableAutoPresence: true,
  enableGoogleMeet: true,
  presenceUpdateInterval: 5000,
  showAvatars: true,
  highlightSameFile: true,
  statusBarTiles: ['online', 'same-file', 'workspace']
};

const snapshot: TeamHubSnapshot = {
  currentUser: {
    id: 'you',
    displayName: 'You',
    status: 'online',
    currentFile: 'api/auth.ts',
    workspace: 'backend',
    lastSeen: Date.now()
  },
  users: [
    { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, lastSeen: Date.now(), workspace: 'backend' },
    { id: 'bob', displayName: 'Bob Kumar', status: 'away', currentFile: 'utils/logger.ts', currentLine: 58, lastSeen: Date.now(), workspace: 'backend' },
    { id: 'carol', displayName: 'Carol Wang', status: 'offline', lastSeen: Date.now(), workspace: 'platform' }
  ],
  groupedUsers: {
    online: [
      { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, lastSeen: Date.now(), workspace: 'backend' }
    ],
    away: [
      { id: 'bob', displayName: 'Bob Kumar', status: 'away', currentFile: 'utils/logger.ts', currentLine: 58, lastSeen: Date.now(), workspace: 'backend' }
    ],
    offline: [
      { id: 'carol', displayName: 'Carol Wang', status: 'offline', lastSeen: Date.now(), workspace: 'platform' }
    ]
  },
  currentFile: 'api/auth.ts',
  sameFileUsers: [
    { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, lastSeen: Date.now(), workspace: 'backend' }
  ],
  updatedAt: Date.now()
};

describe('Team Hub status bar tiles', () => {
  it('builds the requested tile specs in order', () => {
    const tiles = buildTeamHubStatusBarTileSpecs(snapshot, config);

    expect(tiles.map((tile) => tile.id)).toEqual(['online', 'same-file', 'workspace']);
    expect(tiles[0].text).toContain('1');
    expect(tiles[1].text).toContain('1');
    expect(tiles[2].text).toContain('backend');
  });

  it('falls back to the default tile set when none are configured', () => {
    const tiles = buildTeamHubStatusBarTileSpecs(snapshot, {
      ...config,
      statusBarTiles: []
    });

    expect(tiles.map((tile) => tile.id)).toEqual(['online', 'same-file', 'workspace']);
  });
});