import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ConflictPredictionService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn(),
    fatal: vi.fn()
  })
}));

describe('ConflictPredictionService', () => {
  let service: ConflictPredictionService;
  let mockPool: any;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn().mockResolvedValue({ rows: [] }),
      release: vi.fn()
    };

    mockPool = {
      connect: vi.fn().mockResolvedValue(mockClient)
    };

    service = new ConflictPredictionService(mockPool);
  });

  it('initializes tables on startup', async () => {
    await service.initialize();
    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS conflict_logs'));
  });

  it('detects and emits conflict when two users edit the same file', async () => {
    const conflictSpy = vi.fn();
    service.on('conflict-detected', conflictSpy);

    await service.reportActivity('user1', 'src/shared.ts', null);
    await service.reportActivity('user2', 'src/shared.ts', null);

    expect(conflictSpy).toHaveBeenCalled();
    const alert = conflictSpy.mock.calls[0][0];
    expect(alert.targetUserId).toBe('user2');
    expect(alert.otherUserId).toBe('user1');
    expect(alert.filePath).toBe('src/shared.ts');
  });

  it('detects specific function-level overlaps', async () => {
    const conflictSpy = vi.fn();
    service.on('conflict-detected', conflictSpy);

    await service.reportActivity('user1', 'src/logic.ts', 'calculateTax');
    await service.reportActivity('user2', 'src/logic.ts', 'calculateTax');

    expect(conflictSpy).toHaveBeenCalled();
    const alert = conflictSpy.mock.calls[0][0];
    expect(alert.riskScore).toBe(90);
    expect(alert.message).toContain('calculateTax');
  });

  it('does not alert for different files', async () => {
    const conflictSpy = vi.fn();
    service.on('conflict-detected', conflictSpy);

    await service.reportActivity('user1', 'src/a.ts', null);
    await service.reportActivity('user2', 'src/b.ts', null);

    expect(conflictSpy).not.toHaveBeenCalled();
  });
});
