import * as vscode from 'vscode';
export const readTeamHubConfig = () => {
    const config = vscode.workspace.getConfiguration('teamHub');
    return {
        matrixHomeserver: config.get('matrixHomeserver', '').trim(),
        roomId: config.get('roomId', '').trim(),
        presenceSidecarUrl: config.get('presenceSidecarUrl', '').trim(),
        enableAutoPresence: config.get('enableAutoPresence', true),
        enableGoogleMeet: config.get('enableGoogleMeet', true),
        presenceUpdateInterval: config.get('presenceUpdateInterval', 5000),
        showAvatars: config.get('showAvatars', true),
        highlightSameFile: config.get('highlightSameFile', true),
        enableTerminalDLP: config.get('enableTerminalDLP', true)
    };
};
//# sourceMappingURL=config.js.map