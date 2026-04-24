import type { TeamHubSnapshot } from './types';

export const TEAM_HUB_PRIVATE_VIEW_KEY = 'teamHub.privateViewEnabled';

export const applyUserIsolation = (snapshot: TeamHubSnapshot, privateViewEnabled: boolean): TeamHubSnapshot => {
  if (!privateViewEnabled) {
    return snapshot;
  }

  return {
    ...snapshot,
    users: [],
    groupedUsers: {
      online: [],
      away: [],
      offline: []
    },
    sameFileUsers: []
  };
};
