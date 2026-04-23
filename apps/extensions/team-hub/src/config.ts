import * as vscode from 'vscode';
import type { TeamHubConfig } from './types';

export const readTeamHubConfig = (): TeamHubConfig => {
  const config = vscode.workspace.getConfiguration('teamHub');

  return {
    matrixHomeserver: config.get<string>('matrixHomeserver', '').trim(),
    roomId: config.get<string>('roomId', '').trim(),
    presenceSidecarUrl: config.get<string>('presenceSidecarUrl', '').trim(),
    enableAutoPresence: config.get<boolean>('enableAutoPresence', true),
    enableGoogleMeet: config.get<boolean>('enableGoogleMeet', true),
    presenceUpdateInterval: config.get<number>('presenceUpdateInterval', 5000),
    showAvatars: config.get<boolean>('showAvatars', true),
    highlightSameFile: config.get<boolean>('highlightSameFile', true),
    enableTerminalDLP: config.get<boolean>('enableTerminalDLP', true),
    enableGitHubTaskSync: config.get<boolean>('enableGitHubTaskSync', false),
    githubToken: config.get<string>('githubToken', '').trim() || process.env.GITHUB_TOKEN,
    githubOwner: config.get<string>('githubOwner', '').trim() || process.env.GITHUB_OWNER || 'kushin77',
    githubRepo: config.get<string>('githubRepo', '').trim() || process.env.GITHUB_REPO || 'code-server',
    gitHubTaskSyncInterval: config.get<number>('gitHubTaskSyncInterval', 30000)
  };
};
