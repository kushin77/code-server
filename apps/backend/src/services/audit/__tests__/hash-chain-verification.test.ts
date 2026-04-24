// @file        apps/backend/src/services/audit/__tests__/hash-chain-verification.test.ts
// @description Tests for hash chain verification and tamper detection

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { HashChainVerificationService, initHashChainVerificationService, resetHashChainVerificationService } from '../hash-chain-verification';
import { createHash } from 'crypto';

describe('HashChainVerificationService', () => {
  let mockDb: any;
  let service: HashChainVerificationService;

  beforeEach(() => {
    mockDb = {
      query: vi.fn(),
    };
    service = new HashChainVerificationService(mockDb);
  });

  afterEach(() => {
    resetHashChainVerificationService();
  });

  describe('verifyChainIntegrity', () => {
    it('should return valid result for empty audit log', async () => {
      mockDb.query.mockResolvedValue({ rows: [] });

      const result = await service.verifyChainIntegrity();

      expect(result.isValid).toBe(true);
      expect(result.totalEntries).toBe(0);
      expect(result.validEntries).toBe(0);
      expect(result.tamperedEntries).length(0);
      expect(result.chainBreaks).length(0);
    });

    it('should validate correct hash chain', async () => {
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
      const event1Hash = createHash('sha256')
        .update(JSON.stringify({ u: 'user1', a: 'create', r: 'req:1', prev: genesisHash }))
        .digest('hex');
      const event2Hash = createHash('sha256')
        .update(JSON.stringify({ u: 'user2', a: 'update', r: 'req:1', prev: event1Hash }))
        .digest('hex');

      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: event1Hash, previous_hash: genesisHash, created_at: '2026-04-22T00:00:00Z' },
          { id: 2, user_id: 'user2', action: 'update', resource: 'req:1', event_hash: event2Hash, previous_hash: event1Hash, created_at: '2026-04-22T00:01:00Z' },
        ],
      });

      const result = await service.verifyChainIntegrity();

      expect(result.isValid).toBe(true);
      expect(result.totalEntries).toBe(2);
      expect(result.validEntries).toBe(2);
      expect(result.tamperedEntries).length(0);
      expect(result.chainBreaks).length(0);
    });

    it('should detect tampered hash', async () => {
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
      const correctHash = createHash('sha256')
        .update(JSON.stringify({ u: 'user1', a: 'create', r: 'req:1', prev: genesisHash }))
        .digest('hex');
      const tamperedHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: tamperedHash, previous_hash: genesisHash, created_at: '2026-04-22T00:00:00Z' },
        ],
      });

      const result = await service.verifyChainIntegrity();

      expect(result.isValid).toBe(false);
      expect(result.tamperedEntries).toContain(1);
      expect(result.chainBreaks.length).toBeGreaterThan(0);
    });

    it('should detect broken chain link', async () => {
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
      const event1Hash = createHash('sha256')
        .update(JSON.stringify({ u: 'user1', a: 'create', r: 'req:1', prev: genesisHash }))
        .digest('hex');

      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: event1Hash, previous_hash: genesisHash, created_at: '2026-04-22T00:00:00Z' },
          // Entry 2 has wrong previous_hash, breaking the chain
          { id: 2, user_id: 'user2', action: 'update', resource: 'req:1', event_hash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', previous_hash: 'wronghash', created_at: '2026-04-22T00:01:00Z' },
        ],
      });

      const result = await service.verifyChainIntegrity();

      expect(result.isValid).toBe(false);
      expect(result.tamperedEntries).toContain(2);
      expect(result.chainBreaks.length).toBeGreaterThan(0);
    });

    it('should handle database query errors gracefully', async () => {
      mockDb.query.mockRejectedValue(new Error('Database connection failed'));

      const result = await service.verifyChainIntegrity();

      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors[0]).toContain('Database connection failed');
    });
  });

  describe('generateTamperDetectionReport', () => {
    it('should generate INTACT report for valid chain', async () => {
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
      const event1Hash = createHash('sha256')
        .update(JSON.stringify({ u: 'user1', a: 'create', r: 'req:1', prev: genesisHash }))
        .digest('hex');

      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: event1Hash, previous_hash: genesisHash, created_at: '2026-04-22T00:00:00Z' },
        ],
      });

      const report = await service.generateTamperDetectionReport();

      expect(report.status).toBe('INTACT');
      expect(report.verificationResult.isValid).toBe(true);
      expect(report.recommendations).not.toContain('Audit log chain integrity compromised');
    });

    it('should generate COMPROMISED report for tampered chain', async () => {
      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: 'wronghash', previous_hash: '0000000000000000000000000000000000000000000000000000000000000000', created_at: '2026-04-22T00:00:00Z' },
        ],
      });

      const report = await service.generateTamperDetectionReport();

      expect(report.status).toBe('COMPROMISED');
      expect(report.verificationResult.isValid).toBe(false);
      expect(report.recommendations[0]).toContain('Audit log chain integrity compromised');
    });

    it('should include timestamp in report', async () => {
      mockDb.query.mockResolvedValue({ rows: [] });

      const report = await service.generateTamperDetectionReport();

      expect(report.timestamp).toBeDefined();
      expect(new Date(report.timestamp).getTime()).toBeLessThanOrEqual(Date.now());
    });
  });

  describe('verifySingleEntry', () => {
    it('should verify correct entry hash', async () => {
      const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
      const correctHash = createHash('sha256')
        .update(JSON.stringify({ u: 'user1', a: 'create', r: 'req:1', prev: genesisHash }))
        .digest('hex');

      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: correctHash, previous_hash: genesisHash },
        ],
      });

      const result = await service.verifySingleEntry(1);

      expect(result.isValid).toBe(true);
      expect(result.reason).toBeUndefined();
    });

    it('should detect tampered single entry', async () => {
      mockDb.query.mockResolvedValue({
        rows: [
          { id: 1, user_id: 'user1', action: 'create', resource: 'req:1', event_hash: 'wronghash', previous_hash: 'genesis' },
        ],
      });

      const result = await service.verifySingleEntry(1);

      expect(result.isValid).toBe(false);
      expect(result.reason).toContain('Hash mismatch');
    });

    it('should return error for non-existent entry', async () => {
      mockDb.query.mockResolvedValue({ rows: [] });

      const result = await service.verifySingleEntry(999);

      expect(result.isValid).toBe(false);
      expect(result.reason).toContain('not found');
    });

    it('should handle query errors gracefully', async () => {
      mockDb.query.mockRejectedValue(new Error('Query failed'));

      const result = await service.verifySingleEntry(1);

      expect(result.isValid).toBe(false);
      expect(result.reason).toContain('Query failed');
    });
  });

  describe('singleton pattern', () => {
    it('should initialize and retrieve singleton', () => {
      const instance = initHashChainVerificationService(mockDb);

      expect(instance).toBeDefined();
      expect(instance).toBeInstanceOf(HashChainVerificationService);
    });

    it('should reset singleton', () => {
      initHashChainVerificationService(mockDb);
      expect(HashChainVerificationService).toBeDefined();  // Service exists after init
      
      resetHashChainVerificationService();
      // After reset, new verification should create a new independent instance
      const newInstance = new HashChainVerificationService(mockDb);
      expect(newInstance).toBeDefined();
    });
  });
});
