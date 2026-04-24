import { describe, it, expect, beforeEach, vi } from 'vitest';
import { execFileSync } from 'child_process';
import { WorkspaceForkingService } from '../index';
vi.mock('child_process', () => ({
    execFileSync: vi.fn()
}));
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('WorkspaceForkingService', () => {
    let service;
    let mockPool;
    let mockClient;
    const mockedExecFileSync = vi.mocked(execFileSync);
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn()
        };
        mockPool = {
            connect: vi.fn().mockResolvedValue(mockClient)
        };
        service = new WorkspaceForkingService(mockPool);
        mockedExecFileSync.mockReset();
    });
    it('should initialize service and create tables', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('workspace_forks'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should create a workspace fork from HEAD', async () => {
        mockedExecFileSync.mockReturnValueOnce('abc12345\n');
        mockedExecFileSync.mockReturnValueOnce('');
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'fork-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD',
                    base_commit: 'abc12345',
                    fork_branch: 'fork/user-1/abc12345',
                    description: 'exploration',
                    archived: false,
                    created_at: new Date(),
                    archived_at: null
                }]
        });
        const fork = await service.createFork({
            userId: 'user-1',
            repoPath: 'C:/repo',
            description: 'exploration'
        });
        expect(fork.id).toBe('fork-1');
        expect(fork.forkBranch).toContain('fork/user-1');
    });
    it('should create a workspace fork with custom branch name', async () => {
        mockedExecFileSync.mockReturnValueOnce('def67890\n');
        mockedExecFileSync.mockReturnValueOnce('');
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'fork-2',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'main',
                    base_commit: 'def67890',
                    fork_branch: 'explore/feature-x',
                    description: null,
                    archived: false,
                    created_at: new Date(),
                    archived_at: null
                }]
        });
        const fork = await service.createFork({
            userId: 'user-1',
            repoPath: 'C:/repo',
            baseRef: 'main',
            forkBranch: 'explore/feature-x'
        });
        expect(fork.forkBranch).toBe('explore/feature-x');
    });
    it('should list workspace forks', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'fork-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD',
                    base_commit: 'abc12345',
                    fork_branch: 'fork/user-1/abc12345',
                    description: 'exploration',
                    archived: false,
                    created_at: new Date(),
                    archived_at: null
                }
            ]
        });
        const forks = await service.listForks('user-1', 'C:/repo');
        expect(forks).toHaveLength(1);
        expect(forks[0].forkBranch).toContain('fork/user-1');
    });
    it('should get a workspace fork by id', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'fork-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD',
                    base_commit: 'abc12345',
                    fork_branch: 'fork/user-1/abc12345',
                    description: 'exploration',
                    archived: false,
                    created_at: new Date(),
                    archived_at: null
                }
            ]
        });
        const fork = await service.getFork('fork-1');
        expect(fork?.id).toBe('fork-1');
    });
    it('should return null for missing workspace fork', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const fork = await service.getFork('missing');
        expect(fork).toBeNull();
    });
    it('should archive a workspace fork', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'fork-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD',
                    base_commit: 'abc12345',
                    fork_branch: 'fork/user-1/abc12345',
                    description: 'exploration',
                    archived: true,
                    created_at: new Date(),
                    archived_at: new Date()
                }
            ]
        });
        const fork = await service.archiveFork('fork-1');
        expect(fork.archived).toBe(true);
    });
    it('should emit fork-created event', async () => {
        let emittedEvent;
        service.on('fork-created', event => {
            emittedEvent = event;
        });
        mockedExecFileSync.mockReturnValueOnce('abc12345\n');
        mockedExecFileSync.mockReturnValueOnce('');
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'fork-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD',
                    base_commit: 'abc12345',
                    fork_branch: 'fork/user-1/abc12345',
                    description: 'exploration',
                    archived: false,
                    created_at: new Date(),
                    archived_at: null
                }]
        });
        await service.createFork({ userId: 'user-1', repoPath: 'C:/repo' });
        expect(emittedEvent.id).toBe('fork-1');
    });
    it('should emit fork-archived event', async () => {
        let emittedEvent;
        service.on('fork-archived', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'fork-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD',
                    base_commit: 'abc12345',
                    fork_branch: 'fork/user-1/abc12345',
                    description: 'exploration',
                    archived: true,
                    created_at: new Date(),
                    archived_at: new Date()
                }
            ]
        });
        await service.archiveFork('fork-1');
        expect(emittedEvent.id).toBe('fork-1');
    });
});
//# sourceMappingURL=workspace-forking.test.js.map