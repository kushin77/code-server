import { afterEach, describe, expect, it, vi } from 'vitest';

const hoisted = vi.hoisted(() => {
  const emitSpy = vi.fn();
  const watcher = {
    on: vi.fn().mockReturnThis(),
  };
  let callback: ((eventType: 'change' | 'rename', fileName: string | Buffer | null) => void) | null = null;

  const watch = vi.fn((_rootPath: string, _options: unknown, onChange: (eventType: 'change' | 'rename', fileName: string | Buffer | null) => void) => {
    callback = onChange;
    return watcher;
  });

  return {
    emitSpy,
    watch,
    watcher,
    getCallback: () => callback,
  };
});

vi.mock('node:fs', () => ({
  watch: hoisted.watch,
}));

vi.mock('../../audit/audit-service', () => ({
  getAuditService: vi.fn(() => ({
    emit: hoisted.emitSpy,
  })),
}));

import { RepositoryIndexer, startRepositoryFileWatcher } from '../indexing';

describe('startRepositoryFileWatcher', () => {
  afterEach(() => {
    hoisted.emitSpy.mockClear();
    hoisted.watch.mockClear();
    vi.useRealTimers();
  });

  it('emits a file-read audit event before indexing a watched file', async () => {
    vi.useFakeTimers();

    const indexer = {
      processFileChange: vi.fn().mockResolvedValue(true),
    } as unknown as RepositoryIndexer;
    const readFile = vi.fn().mockResolvedValue('export function demo() { return 1 }');
    const onEvent = vi.fn();

    startRepositoryFileWatcher('/repo', indexer, readFile, onEvent, { debounceMs: 25 });

    const callback = hoisted.getCallback();
    expect(callback).not.toBeNull();

    callback?.('change', 'src/demo.ts');
    await vi.advanceTimersByTimeAsync(25);

    expect(readFile).toHaveBeenCalledWith('src/demo.ts');
    expect(hoisted.emitSpy).toHaveBeenCalledOnce();
    expect(hoisted.emitSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        method: 'READ',
        path: 'src/demo.ts',
        resourceType: 'file',
        fileAction: 'read',
      })
    );
    expect(indexer.processFileChange).toHaveBeenCalledWith('src/demo.ts', 'export function demo() { return 1 }');
    expect(onEvent).toHaveBeenCalledWith({ eventType: 'change', filePath: 'src/demo.ts', indexed: true });
  });
});