// @file        apps/backend/src/services/audit/audit-migration.ts
// @module      audit/migration
// @description Idempotent schema migration for the audit_logs table.
//              Safe to call multiple times (CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS).

import { readFileSync } from 'fs';
import { join } from 'path';
import { getLogger } from '../../lib/logger';

const logger = getLogger('AuditMigration');

/** Minimal DB interface — satisfied by any pg Pool/Client. */
export interface MigrationDb {
  query(sql: string, params?: unknown[]): Promise<unknown>;
}

/**
 * Run the Phase 4 audit schema migration idempotently.
 * Reads config/iam/audit-logging-phase4.sql from the repo root and executes it.
 *
 * @param db    Any pg Pool/Client with a query() method
 * @param sqlPath  Override the default SQL path (used in tests)
 */
export async function runAuditMigration(
  db: MigrationDb,
  sqlPath?: string
): Promise<void> {
  const resolvedPath =
    sqlPath ??
    join(process.cwd(), 'config', 'iam', 'audit-logging-phase4.sql');

  logger.info('Running Phase 4 audit schema migration', { path: resolvedPath });

  const sql = readFileSync(resolvedPath, 'utf8');
  await db.query(sql);

  logger.info('Phase 4 audit schema migration complete');
}
