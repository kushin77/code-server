import { describe, expect, it } from 'vitest';
import { buildMentionText, buildMeetLink, buildWorkspaceShareLink } from '../src/collaboration-utils';
import { buildTeamHubSnapshot, findSameFileUsers, groupUsersByStatus } from '../src/presence-model';
import { renderTeamHubWebviewHtml } from '../src/webview';
const config = {
    matrixHomeserver: '',
    roomId: '',
    presenceSidecarUrl: '',
    enableAutoPresence: true,
    enableGoogleMeet: true,
    presenceUpdateInterval: 5000,
    showAvatars: true,
    highlightSameFile: true
};
const users = [
    { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, currentFunction: 'handleLoginCallback', currentTask: 'Polish OAuth flow', customStatus: 'Pairing on auth', lastSeen: Date.now() },
    { id: 'bob', displayName: 'Bob Kumar', status: 'away', currentFile: 'utils/logger.ts', currentLine: 58, currentFunction: 'formatLogEntry', currentTask: 'Harden log redaction', customStatus: 'Reviewing telemetry', lastSeen: Date.now() }
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
        const snapshot = buildTeamHubSnapshot({ id: 'you', displayName: 'You', status: 'online', currentFile: 'api/auth.ts', currentLine: 18, currentFunction: 'seedCurrentUser', currentTask: 'Triaging presence sync', customStatus: 'Available for review', lastSeen: Date.now() }, users, 'api/auth.ts');
        expect(snapshot.sameFileUsers).toHaveLength(1);
        expect(snapshot.currentFile).toBe('api/auth.ts');
    });
    it('builds collaboration actions', () => {
        expect(buildMentionText(users[0])).toBe('@Alice Chen');
        expect(buildMeetLink(users)).toContain('meet.google.com/new');
        expect(buildWorkspaceShareLink('vscode://workspace', 'api/auth.ts')).toContain('vscode://workspace');
    });
    it('renders the sidebar html with key sections', () => {
        const snapshot = buildTeamHubSnapshot({ id: 'you', displayName: 'You', status: 'online', currentFile: 'api/auth.ts', currentLine: 18, currentFunction: 'seedCurrentUser', currentTask: 'Triaging presence sync', customStatus: 'Available for review', lastSeen: Date.now() }, users, 'api/auth.ts');
        const html = renderTeamHubWebviewHtml(snapshot, config, { cspSource: 'vscode-resource:' });
        expect(html).toContain('Team Hub');
        expect(html).toContain('Online (1)');
        expect(html).toContain('Away (1)');
        expect(html).toContain('Same file');
        expect(html).toContain('Function: handleLoginCallback');
        expect(html).toContain('Task: Triaging presence sync');
        expect(html).toContain('Custom status: Available for review');
        expect(html).toContain('Start Meet');
    });
});
//# sourceMappingURL=team-hub.test.js.map