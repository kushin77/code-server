import { describe, it, expect, beforeEach, vi } from 'vitest';
import { KeyboardShortcutManagerService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('KeyboardShortcutManagerService', () => {
    let service;
    let mockPool;
    let mockClient;
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn()
        };
        mockPool = {
            connect: vi.fn().mockResolvedValue(mockClient)
        };
        service = new KeyboardShortcutManagerService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        for (let i = 0; i < 10; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('shortcut_profiles'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should create a profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'prof-1' }]
        });
        const profileId = await service.createProfile('VS Code', 'VS Code default keybindings', 'user-1', { 'Ctrl+S': 'save', 'Ctrl+Z': 'undo' });
        expect(profileId).toBe('prof-1');
    });
    it('should get a profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'VS Code',
                    description: 'VS Code default keybindings',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'save', 'Ctrl+Z': 'undo' }
                }]
        });
        const profile = await service.getProfile('prof-1');
        expect(profile).not.toBeNull();
        expect(profile?.name).toBe('VS Code');
        expect(profile?.shortcuts).toBeDefined();
    });
    it('should return null for non-existent profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const profile = await service.getProfile('non-existent');
        expect(profile).toBeNull();
    });
    it('should get org default profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'Org Default',
                    description: 'Organization default',
                    is_org_default: true,
                    created_by: 'admin',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+K': 'command-palette' }
                }]
        });
        const profile = await service.getOrgDefaultProfile();
        expect(profile).not.toBeNull();
        expect(profile?.isOrgDefault).toBe(true);
    });
    it('should set personal overrides', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.setPersonalOverrides('user-1', 'prof-1', { 'Ctrl+S': 'custom-save' });
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO personal_shortcut_overrides'), expect.any(Array));
    });
    it('should get personal overrides', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    overrides: { 'Ctrl+S': 'custom-save', 'Ctrl+Z': 'custom-undo' }
                }]
        });
        const overrides = await service.getPersonalOverrides('user-1', 'prof-1');
        expect(overrides).not.toBeNull();
        expect(overrides?.['Ctrl+S']).toBe('custom-save');
    });
    it('should get merged shortcuts', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'VS Code',
                    description: 'VS Code',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'save', 'Ctrl+Z': 'undo' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    overrides: { 'Ctrl+S': 'custom-save' }
                }]
        });
        const merged = await service.getMergedShortcuts('user-1', 'prof-1');
        expect(merged['Ctrl+S']).toBe('custom-save');
        expect(merged['Ctrl+Z']).toBe('undo');
    });
    it('should detect clashes between profiles', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'VSCode',
                    description: '',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'save', 'Ctrl+K': 'command-palette' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-2',
                    name: 'Vim',
                    description: '',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'suspend', 'Ctrl+K': 'digraph' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        const clashes = await service.detectClashes('prof-1', 'prof-2');
        expect(clashes.length).toBeGreaterThan(0);
        expect(clashes[0].shortcut).toBeDefined();
        expect(clashes[0].severity).toMatch(/high|medium|low/);
    });
    it('should track shortcut usage', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.trackUsage('user-1', 'Ctrl+S', 'save');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO shortcut_usage_tracking'), expect.any(Array));
    });
    it('should get top shortcuts for user', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { shortcut_key: 'Ctrl+S', command: 'save', usage_count: 150 },
                { shortcut_key: 'Ctrl+Z', command: 'undo', usage_count: 120 }
            ]
        });
        const top = await service.getTopShortcuts('user-1');
        expect(top.length).toBe(2);
        expect(top[0].shortcut_key).toBe('Ctrl+S');
    });
    it('should sync profile to team', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.syncProfileToTeam('prof-1', 'team-1');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO shortcut_team_sync'), expect.any(Array));
    });
    it('should get team synced profiles', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'Team Profile',
                    description: 'Shared team profile',
                    is_org_default: false,
                    created_by: 'admin',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+K': 'command-palette' }
                }]
        });
        const profiles = await service.getTeamSyncedProfiles('team-1');
        expect(profiles.length).toBe(1);
        expect(profiles[0].name).toBe('Team Profile');
    });
    it('should quick switch profiles', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    overrides: { 'Ctrl+S': 'custom-save' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.quickSwitch('user-1', 'prof-1', 'prof-2');
        expect(mockClient.query).toHaveBeenCalled();
    });
    it('should list profiles', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'prof-1',
                    name: 'VS Code',
                    description: 'VS Code',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: {}
                }
            ]
        });
        const profiles = await service.listProfiles();
        expect(profiles.length).toBe(1);
    });
    it('should delete profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.deleteProfile('prof-1');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('DELETE FROM shortcut_profiles'), expect.any(Array));
    });
    it('should update profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.updateProfile('prof-1', 'New Name', 'New Description', { 'Ctrl+S': 'save' });
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE shortcut_profiles'), expect.any(Array));
    });
    it('should cleanup old usage data', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 500
        });
        const count = await service.cleanupOldUsageData(90);
        expect(count).toBe(500);
    });
    it('should emit profile-created event', async () => {
        let emittedEvent;
        service.on('profile-created', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'prof-1' }]
        });
        await service.createProfile('Test', 'Test profile', 'user-1', {});
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.profileId).toBe('prof-1');
    });
    it('should emit overrides-set event', async () => {
        let emittedEvent;
        service.on('overrides-set', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.setPersonalOverrides('user-1', 'prof-1', { 'Ctrl+S': 'custom' });
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('should emit clashes-detected event', async () => {
        let emittedEvent;
        service.on('clashes-detected', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'VSCode',
                    description: '',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'save' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-2',
                    name: 'Vim',
                    description: '',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'suspend' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.detectClashes('prof-1', 'prof-2');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.profileId1).toBe('prof-1');
    });
    it('should emit profile-synced-to-team event', async () => {
        let emittedEvent;
        service.on('profile-synced-to-team', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.syncProfileToTeam('prof-1', 'team-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.teamId).toBe('team-1');
    });
    it('should emit quick-switched event', async () => {
        let emittedEvent;
        service.on('quick-switched', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ overrides: {} }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.quickSwitch('user-1', 'prof-1', 'prof-2');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('should emit profile-updated event', async () => {
        let emittedEvent;
        service.on('profile-updated', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.updateProfile('prof-1', 'New', 'New desc', {});
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.profileId).toBe('prof-1');
    });
    it('should emit profile-deleted event', async () => {
        let emittedEvent;
        service.on('profile-deleted', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.deleteProfile('prof-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.profileId).toBe('prof-1');
    });
    it('should handle profile with no overrides', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'prof-1',
                    name: 'VS Code',
                    description: 'VS Code',
                    is_org_default: false,
                    created_by: 'user-1',
                    created_at: new Date(),
                    shortcuts: { 'Ctrl+S': 'save' }
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const merged = await service.getMergedShortcuts('user-1', 'prof-1');
        expect(merged['Ctrl+S']).toBe('save');
        expect(Object.keys(merged).length).toBe(1);
    });
});
//# sourceMappingURL=keyboard-shortcut-manager.test.js.map