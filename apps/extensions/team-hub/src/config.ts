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
    highlightSameFile: config.get<boolean>('highlightSameFile', true)
  };
};
