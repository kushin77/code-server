import { describe, it, expect, beforeEach, vi } from 'vitest';
import { MultiRootWorkspaceManagerService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('MultiRootWorkspaceManagerService', () => {
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
        service = new MultiRootWorkspaceManagerService(mockPool);
    });
    it('should initialize workspace profile tables', async () => {
        for (let i = 0; i < 8; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('workspace_profiles'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should create a workspace profile with roots', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [
                        { path: '/workspace/alpha', label: 'alpha', primary: true },
                        { path: '/workspace/shared', label: 'shared', primary: false }
                    ],
                    settings: { theme: 'dark' },
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const profile = await service.createProfile({
            userId: 'user-1',
            projectName: 'alpha',
            description: 'Primary project',
            roots: [
                { path: '/workspace/alpha', label: 'alpha' },
                { path: '/workspace/shared', label: 'shared' }
            ],
            settings: { theme: 'dark' },
            isActive: true
        });
        expect(profile.id).toBe('profile-1');
        expect(profile.roots).toHaveLength(2);
    });
    it('should list workspace profiles', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        const profiles = await service.listProfiles('user-1');
        expect(profiles).toHaveLength(1);
        expect(profiles[0].projectName).toBe('alpha');
    });
    it('should get an active workspace profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        const profile = await service.getActiveProfile('user-1');
        expect(profile?.isActive).toBe(true);
        expect(profile?.projectName).toBe('alpha');
    });
    it('should update a workspace profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: { theme: 'dark' },
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha-renamed',
                    description: 'Updated project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: { theme: 'light' },
                    is_active: false,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const updated = await service.updateProfile('profile-1', {
            projectName: 'alpha-renamed',
            description: 'Updated project',
            settings: { theme: 'light' },
            isActive: false
        });
        expect(updated.projectName).toBe('alpha-renamed');
        expect(updated.settings.theme).toBe('light');
    });
    it('should add a root to profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', label: 'alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [
                        { path: '/workspace/alpha', label: 'alpha', primary: true },
                        { path: '/workspace/shared', label: 'shared', primary: false }
                    ],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const profile = await service.addRoot('profile-1', { path: '/workspace/shared', label: 'shared' });
        expect(profile.roots).toHaveLength(2);
        expect(profile.roots[1].path).toBe('/workspace/shared');
    });
    it('should remove a root from profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [
                        { path: '/workspace/alpha', label: 'alpha', primary: true },
                        { path: '/workspace/shared', label: 'shared', primary: false }
                    ],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', label: 'alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const profile = await service.removeRoot('profile-1', '/workspace/shared');
        expect(profile.roots).toHaveLength(1);
        expect(profile.roots[0].path).toBe('/workspace/alpha');
    });
    it('should activate a workspace profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: false,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const profile = await service.activateProfile('profile-1');
        expect(profile.isActive).toBe(true);
    });
    it('should clone a workspace profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: { theme: 'dark' },
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-2',
                    user_id: 'user-1',
                    project_name: 'alpha copy',
                    description: 'Primary project',
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: { theme: 'dark' },
                    is_active: false,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const profile = await service.cloneProfile('profile-1');
        expect(profile.id).toBe('profile-2');
        expect(profile.projectName).toBe('alpha copy');
    });
    it('should delete a workspace profile', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'profile-1', user_id: 'user-1' }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.deleteProfile('profile-1');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('DELETE FROM workspace_profiles'), expect.any(Array));
    });
    it('should emit profile-created event', async () => {
        let emittedEvent;
        service.on('profile-created', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: null,
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.createProfile({
            userId: 'user-1',
            projectName: 'alpha',
            roots: [{ path: '/workspace/alpha' }],
            isActive: true
        });
        expect(emittedEvent.id).toBe('profile-1');
    });
    it('should emit profile-activated event', async () => {
        let emittedEvent;
        service.on('profile-activated', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: null,
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: false,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'profile-1',
                    user_id: 'user-1',
                    project_name: 'alpha',
                    description: null,
                    roots: [{ path: '/workspace/alpha', primary: true }],
                    settings: {},
                    is_active: true,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.activateProfile('profile-1');
        expect(emittedEvent.id).toBe('profile-1');
    });
    it('should return null for missing active profile', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const profile = await service.getActiveProfile('user-1');
        expect(profile).toBeNull();
    });
    it('should reject creating a profile without roots', async () => {
        await expect(service.createProfile({
            userId: 'user-1',
            projectName: 'alpha',
            roots: []
        })).rejects.toThrow('Workspace profile requires at least one root');
    });
});
//# sourceMappingURL=multi-root-workspace-manager.test.js.map