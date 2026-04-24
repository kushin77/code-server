#!/usr/bin/env node
// @file        apps/backend/src/services/backup/index.ts
// @module      services/backup
// @description Backup service module exports
// @owner       Infrastructure Team
// @status      Production-ready - April 23, 2026

export { BackupStrategyService } from './backup-strategy-service';
export type {
  BackupStatus,
  BackupVerification,
  BackupRecord,
  BackupStrategyConfig,
  RestoreProcedure,
} from './backup-strategy-service';

export default BackupStrategyService;
