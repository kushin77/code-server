// @file        apps/backend/src/routes/audit-verification.ts
// @module      routes/audit
// @description HTTP routes for audit log verification and tamper detection

import { Router, Request, Response } from 'express';
import { getHashChainVerificationService } from '../services/audit';
import { getLogger } from '../lib/logger';

const logger = getLogger('AuditVerificationRoutes');

export function initializeAuditVerificationRoutes(router: Router): void {
  /**
   * GET /api/audit/verify
   * Verify the integrity of the audit log hash chain.
   * Returns detailed report of any tampering, missing entries, or chain breaks.
   *
   * Response:
   * - 200: {isValid, totalEntries, validEntries, tamperedEntries[], chainBreaks[], errors[]}
   * - 404: Hash chain verification service not initialized
   */
  router.get('/audit/verify', async (req: Request, res: Response) => {
    const service = getHashChainVerificationService();
    if (!service) {
      return res.status(404).json({
        error: 'Hash chain verification service not initialized',
      });
    }

    try {
      const result = await service.verifyChainIntegrity();
      res.status(200).json(result);
    } catch (err) {
      logger.error('Audit verification failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      res.status(500).json({
        error: 'Audit verification failed',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });

  /**
   * GET /api/audit/tamper-detection-report
   * Generate a compliance report for audit log tampering.
   * Suitable for SOC2 audits, security reviews, and incident investigation.
   *
   * Response:
   * - 200: {timestamp, status, verificationResult, firstTamperAt, affectedRecords, recommendations}
   * - 404: Hash chain verification service not initialized
   */
  router.get('/audit/tamper-detection-report', async (req: Request, res: Response) => {
    const service = getHashChainVerificationService();
    if (!service) {
      return res.status(404).json({
        error: 'Hash chain verification service not initialized',
      });
    }

    try {
      const report = await service.generateTamperDetectionReport();
      res.status(200).json(report);
    } catch (err) {
      logger.error('Tamper detection report generation failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      res.status(500).json({
        error: 'Tamper detection report generation failed',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });

  /**
   * GET /api/audit/verify/:entryId
   * Verify a specific audit log entry against its hash.
   * Useful for spot-checking individual records.
   *
   * Params:
   * - entryId: ID of the audit log entry to verify
   *
   * Response:
   * - 200: {isValid, reason?}
   * - 404: Hash chain verification service not initialized
   */
  router.get('/audit/verify/:entryId', async (req: Request, res: Response) => {
    const service = getHashChainVerificationService();
    if (!service) {
      return res.status(404).json({
        error: 'Hash chain verification service not initialized',
      });
    }

    try {
      const entryId = parseInt(req.params.entryId, 10);
      if (isNaN(entryId)) {
        return res.status(400).json({
          error: 'Invalid entry ID',
        });
      }

      const result = await service.verifySingleEntry(entryId);
      res.status(200).json(result);
    } catch (err) {
      logger.error('Single entry verification failed', {
        error: err instanceof Error ? err.message : String(err),
        entryId: req.params.entryId,
      });
      res.status(500).json({
        error: 'Single entry verification failed',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  });
}
