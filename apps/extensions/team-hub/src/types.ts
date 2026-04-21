export type PresenceStatus = 'online' | 'away' | 'offline';

export type TeamHubStatusBarTileId = 'online' | 'away' | 'offline' | 'same-file' | 'workspace';

export interface TeamHubUser {
  id: string;
  displayName: string;
  status: PresenceStatus;
  currentFile?: string;
  currentLine?: number;
  lastSeen: number;
  workspace?: string;
  avatarUrl?: string;
}

export interface TeamHubConfig {
  matrixHomeserver: string;
  roomId: string;
  presenceSidecarUrl: string;
  enableAutoPresence: boolean;
  enableGoogleMeet: boolean;
  presenceUpdateInterval: number;
  showAvatars: boolean;
  highlightSameFile: boolean;
  statusBarTiles: TeamHubStatusBarTileId[];
}

export interface TeamHubSnapshot {
  currentUser: TeamHubUser;
  users: TeamHubUser[];
  groupedUsers: Record<PresenceStatus, TeamHubUser[]>;
  currentFile?: string;
  sameFileUsers: TeamHubUser[];
  updatedAt: number;
}
