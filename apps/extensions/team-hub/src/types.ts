export type PresenceStatus = 'online' | 'away' | 'offline';

export interface WorkingHours {
  startHour: number;
  endHour: number;
}

export interface TeamHubUser {
  id: string;
  displayName: string;
  status: PresenceStatus;
  currentFile?: string;
  currentLine?: number;
  currentFunction?: string;
  currentTask?: string;
  customStatus?: string;
  timezone?: string;
  workingHours?: WorkingHours;
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
  enableTerminalDLP?: boolean;
}

export interface TeamHubSnapshot {
  currentUser: TeamHubUser;
  users: TeamHubUser[];
  groupedUsers: Record<PresenceStatus, TeamHubUser[]>;
  currentFile?: string;
  sameFileUsers: TeamHubUser[];
  updatedAt: number;
}
