import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const emitSpy = vi.fn();

vi.mock('../../audit/audit-service', () => ({
  getAuditService: vi.fn(() => ({
    emit: emitSpy,
  })),
}));

import { runAuditMigration } from '../audit-migration';

describe('runAuditMigration', () => {
  const tempDirs: string[] = [];

  beforeEach(() => {
    emitSpy.mockClear();
  });

  afterEach(() => {
    while (tempDirs.length > 0) {
      const tempDir = tempDirs.pop();
      if (tempDir) {
        fs.rmSync(tempDir, { recursive: true, force: true });
      }
    }
  });

  it.skip('reads the migration SQL and emits a config audit event', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-migration-'));
    tempDirs.push(tempDir);

    const sqlPath = path.join(tempDir, 'audit-logging-phase4.sql');
    const sql = 'CREATE TABLE audit_logs_test (id uuid primary key);';
    fs.writeFileSync(sqlPath, sql);

    const db = {
      query: vi.fn().mockResolvedValue({}),
    };

    await runAuditMigration(db as never, sqlPath);

    expect(db.query).toHaveBeenCalledOnce();
    expect(db.query).toHaveBeenCalledWith(sql);
    expect(emitSpy).toHaveBeenCalledOnce();
    expect(emitSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        method: 'READ',
        path: sqlPath,
        resourceType: 'config',
        fileAction: 'read',
      })
    );
  });
});