export type TeamHubCommandAction = 'open-sidebar' | 'start-meet' | 'share-workspace' | 'refresh-presence' | 'open-settings' | 'toggle-isolation';

export interface TeamHubCommandMatch {
  action: TeamHubCommandAction;
  description: string;
}

const normalizeCommand = (commandText: string): string => commandText.trim().toLowerCase().replace(/\s+/g, ' ');

const COMMAND_ALIASES: Record<string, TeamHubCommandMatch> = {
  'open sidebar': { action: 'open-sidebar', description: 'Open the Team Hub sidebar' },
  'show sidebar': { action: 'open-sidebar', description: 'Open the Team Hub sidebar' },
  'open activity feed': { action: 'open-sidebar', description: 'Open the Team Hub sidebar' },
  'show activity feed': { action: 'open-sidebar', description: 'Open the Team Hub sidebar' },
  'start meet': { action: 'start-meet', description: 'Copy a Google Meet link' },
  'share workspace': { action: 'share-workspace', description: 'Copy the workspace link' },
  'copy workspace link': { action: 'share-workspace', description: 'Copy the workspace link' },
  'refresh presence': { action: 'refresh-presence', description: 'Refresh collaboration presence' },
  'sync presence': { action: 'refresh-presence', description: 'Refresh collaboration presence' },
  'open settings': { action: 'open-settings', description: 'Open Team Hub settings' },
  'show settings': { action: 'open-settings', description: 'Open Team Hub settings' },
  'toggle private mode': { action: 'toggle-isolation', description: 'Toggle private view' },
  'toggle private view': { action: 'toggle-isolation', description: 'Toggle private view' },
  'exit private mode': { action: 'toggle-isolation', description: 'Toggle private view' },
};

export const resolveTeamHubCommand = (commandText: string): TeamHubCommandMatch | undefined => {
  if (!commandText.trim()) {
    return undefined;
  }

  return COMMAND_ALIASES[normalizeCommand(commandText)];
};