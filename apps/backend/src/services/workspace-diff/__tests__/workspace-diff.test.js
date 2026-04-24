import { describe, it, expect, beforeEach, vi } from 'vitest';
import { execFileSync } from 'child_process';
import { WorkspaceDiffService } from '../index';
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
describe('WorkspaceDiffService', () => {
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
        service = new WorkspaceDiffService(mockPool);
        mockedExecFileSync.mockReset();
    });
    it('should initialize service and create tables', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('workspace_diff_snapshots'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should generate a workspace diff from git output', () => {
        mockedExecFileSync.mockReturnValueOnce('M\tsrc/app.ts\nA\tsrc/new.ts\nD\tsrc/old.ts\n');
        const diff = service.generateDiff('user-1', 'C:/repo', 'HEAD~1', 'HEAD');
        expect(diff.changedFiles).toHaveLength(3);
        expect(diff.summary).toContain('3 files changed');
        expect(diff.changedFiles[0].status).toBe('modified');
    });
    it('should capture a workspace diff with no prior snapshot', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockedExecFileSync.mockReturnValueOnce('M\tsrc/app.ts\n');
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'snapshot-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD~1',
                    head_ref: 'HEAD',
                    summary: '1 files changed: 1 modified',
                    changed_files: [{ status: 'modified', path: 'src/app.ts' }],
                    generated_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const snapshot = await service.captureWorkspaceDiff('user-1', 'C:/repo');
        expect(snapshot.id).toBe('snapshot-1');
        expect(snapshot.changedFiles).toHaveLength(1);
    });
    it('should capture using the previous snapshot head as the new base', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'snapshot-prev',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD~2',
                    head_ref: 'abc123',
                    summary: 'previous',
                    changed_files: [],
                    generated_at: new Date()
                }]
        });
        mockedExecFileSync.mockReturnValueOnce('A\tsrc/new.ts\n');
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'snapshot-2',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'abc123',
                    head_ref: 'HEAD',
                    summary: '1 files changed: 1 added',
                    changed_files: [{ status: 'added', path: 'src/new.ts' }],
                    generated_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const snapshot = await service.captureWorkspaceDiff('user-1', 'C:/repo');
        expect(snapshot.baseRef).toBe('abc123');
    });
    it('should get the latest snapshot', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'snapshot-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD~1',
                    head_ref: 'HEAD',
                    summary: '1 files changed: 1 modified',
                    changed_files: [{ status: 'modified', path: 'src/app.ts' }],
                    generated_at: new Date()
                }]
        });
        const snapshot = await service.getLatestSnapshot({ userId: 'user-1', repoPath: 'C:/repo' });
        expect(snapshot?.id).toBe('snapshot-1');
    });
    it('should list snapshots', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'snapshot-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD~1',
                    head_ref: 'HEAD',
                    summary: '1 files changed: 1 modified',
                    changed_files: [{ status: 'modified', path: 'src/app.ts' }],
                    generated_at: new Date()
                }
            ]
        });
        const snapshots = await service.listSnapshots({ userId: 'user-1', repoPath: 'C:/repo', limit: 5 });
        expect(snapshots).toHaveLength(1);
        expect(snapshots[0].summary).toContain('files changed');
    });
    it('should save snapshot and file details', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'snapshot-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD~1',
                    head_ref: 'HEAD',
                    summary: '1 files changed: 1 modified',
                    changed_files: [{ status: 'modified', path: 'src/app.ts' }],
                    generated_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const snapshot = await service.saveSnapshot({
            userId: 'user-1',
            repoPath: 'C:/repo',
            baseRef: 'HEAD~1',
            headRef: 'HEAD',
            summary: '1 files changed: 1 modified',
            changedFiles: [{ status: 'modified', path: 'src/app.ts' }],
            generatedAt: new Date()
        });
        expect(snapshot.id).toBe('snapshot-1');
    });
    it('should emit workspace-diff-captured event', async () => {
        let emittedEvent;
        service.on('workspace-diff-captured', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockedExecFileSync.mockReturnValueOnce('M\tsrc/app.ts\n');
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'snapshot-1',
                    user_id: 'user-1',
                    repo_path: 'C:/repo',
                    base_ref: 'HEAD~1',
                    head_ref: 'HEAD',
                    summary: '1 files changed: 1 modified',
                    changed_files: [{ status: 'modified', path: 'src/app.ts' }],
                    generated_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.captureWorkspaceDiff('user-1', 'C:/repo');
        expect(emittedEvent.id).toBe('snapshot-1');
    });
    it('should return empty diff summary when no files changed', () => {
        mockedExecFileSync.mockReturnValueOnce('');
        const diff = service.generateDiff('user-1', 'C:/repo', 'HEAD~1', 'HEAD');
        expect(diff.changedFiles).toHaveLength(0);
        expect(diff.summary).toContain('No workspace changes');
    });
});
//# sourceMappingURL=workspace-diff.test.js.map