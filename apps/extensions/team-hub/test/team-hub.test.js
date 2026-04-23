import { describe, expect, it } from 'vitest';
import { buildMentionText, buildMeetLink, buildWorkspaceShareLink, findBestMeetingSlot, formatLocalTime, getWorkingHoursWarning } from '../src/collaboration-utils';
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
    { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, currentFunction: 'handleLoginCallback', currentTask: 'Polish OAuth flow', customStatus: 'Pairing on auth', timezone: 'Europe/London', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() },
    { id: 'bob', displayName: 'Bob Kumar', status: 'away', currentFile: 'utils/logger.ts', currentLine: 58, currentFunction: 'formatLogEntry', currentTask: 'Harden log redaction', customStatus: 'Reviewing telemetry', timezone: 'Asia/Tokyo', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() }
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
    it('formats local time and warns outside working hours', () => {
        const referenceDate = new Date('2026-04-22T14:00:00Z');
        expect(formatLocalTime(referenceDate, 'Asia/Tokyo')).toBe('11:00 PM');
        expect(getWorkingHoursWarning(users[1], referenceDate)).toBe('Its 11 PM for Bob');
    });
    it('finds the best overlap meeting slot', () => {
        const referenceDate = new Date('2026-04-22T14:00:00Z');
        const snapshotUsers = [
            { id: 'you', displayName: 'You', status: 'online', timezone: 'UTC', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() },
            ...users
        ];
        const slot = findBestMeetingSlot(snapshotUsers, referenceDate, 30, 'UTC');
        expect(slot).toBeDefined();
        expect(slot?.availableUsers.map((user) => user.displayName)).toContain('Alice Chen');
        expect(slot?.availableUsers.map((user) => user.displayName)).not.toContain('Bob Kumar');
    });
    it('renders the sidebar html with key sections', () => {
        const snapshot = buildTeamHubSnapshot({ id: 'you', displayName: 'You', status: 'online', currentFile: 'api/auth.ts', currentLine: 18, currentFunction: 'seedCurrentUser', currentTask: 'Triaging presence sync', customStatus: 'Available for review', timezone: 'UTC', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() }, users, 'api/auth.ts');
        snapshot.updatedAt = Date.parse('2026-04-22T14:00:00Z');
        const html = renderTeamHubWebviewHtml(snapshot, config, { cspSource: 'vscode-resource:' });
        expect(html).toContain('Team Hub');
        expect(html).toContain('Online (1)');
        expect(html).toContain('Away (1)');
        expect(html).toContain('Same file');
        expect(html).toContain('Local time');
        expect(html).toContain('Working hours');
        expect(html).toContain('Its 11 PM for Bob');
        expect(html).toContain('Best overlap meeting slot');
        expect(html).toContain('Start Meet');
    });
});
//# sourceMappingURL=team-hub.test.js.map