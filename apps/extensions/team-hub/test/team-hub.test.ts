import { describe, expect, it } from 'vitest';
import { buildMentionText, buildMeetLink, buildWorkspaceShareLink } from '../src/collaboration-utils';
import { buildTeamHubSnapshot, findSameFileUsers, groupUsersByStatus } from '../src/presence-model';
import { renderTeamHubWebviewHtml } from '../src/webview';
import type { TeamHubConfig, TeamHubUser } from '../src/types';

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

const users: TeamHubUser[] = [
  { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, lastSeen: Date.now() },
  { id: 'bob', displayName: 'Bob Kumar', status: 'away', currentFile: 'utils/logger.ts', currentLine: 58, lastSeen: Date.now() }
];

describe('team hub helpers', () => {
  it('groups users by status', () => {
    const grouped = groupUsersByStatus(users);

    expect(grouped.online).toHaveLength(1);
    expect(grouped.away).toHaveLength(1);
    expect(grouped.offline).toHaveLength(0);
  });

  it('finds same-file collaborators', () => {
    const sameFileUsers = findSameFileUsers(users, 'api/auth.ts');

    expect(sameFileUsers.map((user) => user.displayName)).toEqual(['Alice Chen']);
  });

  it('builds a team hub snapshot', () => {
    const snapshot = buildTeamHubSnapshot(
      { id: 'you', displayName: 'You', status: 'online', currentFile: 'api/auth.ts', currentLine: 18, lastSeen: Date.now() },
      users,
      'api/auth.ts'
    );

    expect(snapshot.sameFileUsers).toHaveLength(1);
    expect(snapshot.currentFile).toBe('api/auth.ts');
  });

  it('builds collaboration actions', () => {
    expect(buildMentionText(users[0])).toBe('@Alice Chen');
    expect(buildMeetLink(users)).toContain('meet.google.com/new');
    expect(buildWorkspaceShareLink('vscode://workspace', 'api/auth.ts')).toContain('vscode://workspace');
  });

  it('renders the sidebar html with key sections', () => {
    const snapshot = buildTeamHubSnapshot(
      { id: 'you', displayName: 'You', status: 'online', currentFile: 'api/auth.ts', currentLine: 18, lastSeen: Date.now() },
      users,
      'api/auth.ts'
    );

    const html = renderTeamHubWebviewHtml(snapshot, config, { cspSource: 'vscode-resource:' } as never);

    expect(html).toContain('Team Hub');
    expect(html).toContain('Online (1)');
    expect(html).toContain('Away (1)');
    expect(html).toContain('Same file');
    expect(html).toContain('Start Meet');
  });
});
