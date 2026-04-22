// @file        apps/backend/src/services/audit/index.ts
// @module      audit
// @description Audit service exports (logging and tamper detection)

export {
  AuditService,
  AuditEvent,
  AuditAction,
  IdentityType,
  ResourceType,
  AuditDb,
  initAuditService,
  getAuditService,
  resetAuditService,
} from './audit-service';

export {
  HashChainVerificationService,
  ChainVerificationResult,
  TamperDetectionReport,
  AuditLogEntry,
  HashChainDb,
  initHashChainVerificationService,
  getHashChainVerificationService,
  resetHashChainVerificationService,
} from './hash-chain-verification';
