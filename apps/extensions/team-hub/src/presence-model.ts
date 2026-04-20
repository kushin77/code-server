import type { PresenceStatus, TeamHubSnapshot, TeamHubUser } from './types';

const BASE_USERS: TeamHubUser[] = [
  { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, lastSeen: Date.now() - 12000, workspace: 'backend' },
  { id: 'bob', displayName: 'Bob Kumar', status: 'online', currentFile: 'utils/logger.ts', currentLine: 58, lastSeen: Date.now() - 18000, workspace: 'backend' },
  { id: 'carol', displayName: 'Carol Wang', status: 'online', currentFile: 'tests/e2e.spec.ts', currentLine: 87, lastSeen: Date.now() - 22000, workspace: 'tests' },
  { id: 'dave', displayName: 'Dave Lee', status: 'away', currentFile: 'docs/runbooks.md', currentLine: 19, lastSeen: Date.now() - 900000, workspace: 'docs' },
  { id: 'eve', displayName: 'Eve Park', status: 'offline', lastSeen: Date.now() - 5400000, workspace: 'platform' },
  { id: 'frank', displayName: 'Frank Wu', status: 'offline', lastSeen: Date.now() - 7200000, workspace: 'platform' }
];

export const cloneUsers = (users: TeamHubUser[]): TeamHubUser[] => users.map((user) => ({ ...user }));

export const groupUsersByStatus = (users: TeamHubUser[]): Record<PresenceStatus, TeamHubUser[]> => ({
  online: users.filter((user) => user.status === 'online'),
  away: users.filter((user) => user.status === 'away'),
  offline: users.filter((user) => user.status === 'offline')
});

export const findSameFileUsers = (users: TeamHubUser[], currentFile?: string): TeamHubUser[] => {
  if (!currentFile) {
    return [];
  }

  return users.filter((user) => user.currentFile === currentFile);
};

export const createDefaultCurrentUser = (): TeamHubUser => ({
  id: 'you',
  displayName: 'You',
  status: 'online',
  lastSeen: Date.now()
});

export const createDemoUsers = (): TeamHubUser[] => cloneUsers(BASE_USERS);

export const buildTeamHubSnapshot = (currentUser: TeamHubUser, users: TeamHubUser[], currentFile?: string): TeamHubSnapshot => ({
  currentUser: { ...currentUser },
  users: cloneUsers(users),
  groupedUsers: groupUsersByStatus(users),
  currentFile,
  sameFileUsers: findSameFileUsers(users, currentFile),
  updatedAt: Date.now()
});
