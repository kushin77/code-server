import type { TeamHubUser } from './types';

const slugify = (value: string): string => value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

export const buildMentionText = (user: TeamHubUser): string => `@${user.displayName}`;

export const buildMeetLink = (users: TeamHubUser[]): string => {
  const participantSlug = users.length > 0 ? slugify(users.map((user) => user.displayName).join('-')) : 'team-hub';
  return `https://meet.google.com/new?team=${encodeURIComponent(participantSlug)}`;
};

export const buildWorkspaceShareLink = (workspaceRoot: string, currentFile?: string): string => {
  return currentFile ? `${workspaceRoot}#${encodeURIComponent(currentFile)}` : workspaceRoot;
};
