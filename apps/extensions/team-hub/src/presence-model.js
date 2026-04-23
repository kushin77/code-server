const DEFAULT_TIMEZONE = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
const cloneWorkingHours = (workingHours) => {
    if (!workingHours) {
        return undefined;
    }
    return { ...workingHours };
};
export const cloneUser = (user) => ({
    ...user,
    workingHours: cloneWorkingHours(user.workingHours)
});
const BASE_USERS = [
    { id: 'alice', displayName: 'Alice Chen', status: 'online', currentFile: 'api/auth.ts', currentLine: 142, currentFunction: 'handleLoginCallback', currentTask: 'Polish OAuth flow', customStatus: 'Pairing on auth', timezone: 'Europe/London', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() - 12000, workspace: 'backend' },
    { id: 'bob', displayName: 'Bob Kumar', status: 'online', currentFile: 'utils/logger.ts', currentLine: 58, currentFunction: 'formatLogEntry', currentTask: 'Harden log redaction', customStatus: 'Reviewing telemetry', timezone: 'Asia/Tokyo', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() - 18000, workspace: 'backend' },
    { id: 'carol', displayName: 'Carol Wang', status: 'online', currentFile: 'tests/e2e.spec.ts', currentLine: 87, currentFunction: 'runCollabSmokeSuite', currentTask: 'Stabilize collaboration tests', customStatus: 'On test duty', timezone: 'America/New_York', workingHours: { startHour: 9, endHour: 17 }, lastSeen: Date.now() - 22000, workspace: 'tests' },
    { id: 'dave', displayName: 'Dave Lee', status: 'away', currentFile: 'docs/runbooks.md', currentLine: 19, currentFunction: 'updateRunbookEntry', currentTask: 'Document failover notes', customStatus: 'Back soon', timezone: 'America/Los_Angeles', workingHours: { startHour: 8, endHour: 16 }, lastSeen: Date.now() - 900000, workspace: 'docs' },
    { id: 'eve', displayName: 'Eve Park', status: 'offline', currentTask: 'Offline', customStatus: 'Out of office', timezone: 'Europe/Berlin', workingHours: { startHour: 10, endHour: 18 }, lastSeen: Date.now() - 5400000, workspace: 'platform' },
    { id: 'frank', displayName: 'Frank Wu', status: 'offline', currentTask: 'Offline', customStatus: 'Deep work', timezone: 'Australia/Sydney', workingHours: { startHour: 8, endHour: 16 }, lastSeen: Date.now() - 7200000, workspace: 'platform' }
];
export const cloneUsers = (users) => users.map((user) => cloneUser(user));
export const groupUsersByStatus = (users) => ({
    online: users.filter((user) => user.status === 'online'),
    away: users.filter((user) => user.status === 'away'),
    offline: users.filter((user) => user.status === 'offline')
});
export const findSameFileUsers = (users, currentFile) => {
    if (!currentFile) {
        return [];
    }
    return users.filter((user) => user.currentFile === currentFile);
};
export const createDefaultCurrentUser = () => ({
    id: 'you',
    displayName: 'You',
    status: 'online',
    customStatus: 'Available',
    timezone: DEFAULT_TIMEZONE,
    workingHours: { startHour: 9, endHour: 17 },
    lastSeen: Date.now()
});
export const createDemoUsers = () => cloneUsers(BASE_USERS);
export const buildTeamHubSnapshot = (currentUser, users, currentFile) => ({
    currentUser: cloneUser(currentUser),
    users: cloneUsers(users),
    groupedUsers: groupUsersByStatus(users),
    currentFile,
    sameFileUsers: findSameFileUsers(users, currentFile),
    updatedAt: Date.now()
});
//# sourceMappingURL=presence-model.js.map