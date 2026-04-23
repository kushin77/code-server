// @file        apps/backend/src/services/audit/hash-chain-verification.ts
// @module      audit/tamper-detection
// @description Hash chain verification service for detecting audit log tampering
//              Validates continuous hash chain integrity per SOC2 requirements.
import { createHash } from 'crypto';
import { getLogger } from '../../lib/logger';
const logger = getLogger('HashChainVerification');
// ── Service ───────────────────────────────────────────────────────────────────
export class HashChainVerificationService {
    constructor(db) {
        this.db = db;
    }
    /**
     * Verify the integrity of the audit log hash chain.
     * Returns detailed report of any tampering, missing entries, or chain breaks.
     */
    async verifyChainIntegrity() {
        try {
            // Load all audit log entries in order
            const result = await this.db.query('SELECT id, user_id, action, resource, event_hash, previous_hash, created_at FROM audit_logs ORDER BY id ASC');
            const entries = result?.rows || [];
            const verificationResult = {
                isValid: true,
                totalEntries: entries.length,
                validEntries: 0,
                tamperedEntries: [],
                missingEntries: [],
                chainBreaks: [],
                errors: [],
            };
            if (entries.length === 0) {
                return verificationResult;
            }
            // Verify first entry has genesis hash
            const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
            if (entries[0].previous_hash !== genesisHash) {
                verificationResult.chainBreaks.push({
                    after: 0,
                    reason: `First entry should reference genesis hash, got: ${entries[0].previous_hash}`,
                });
                verificationResult.isValid = false;
            }
            // Verify each entry's hash matches the recalculated hash
            for (let i = 0; i < entries.length; i++) {
                const entry = entries[i];
                const prevEntry = i > 0 ? entries[i - 1] : null;
                // Check that previous_hash matches previous entry's event_hash
                const expectedPrevHash = prevEntry?.event_hash || genesisHash;
                if (entry.previous_hash !== expectedPrevHash) {
                    verificationResult.tamperedEntries.push(entry.id);
                    verificationResult.chainBreaks.push({
                        after: i,
                        reason: `Entry ${entry.id}: previous_hash mismatch. Expected ${expectedPrevHash}, got ${entry.previous_hash}`,
                    });
                    verificationResult.isValid = false;
                }
                // Recalculate hash and verify it matches stored hash
                const recalculatedHash = this._recalculateHash(entry);
                if (entry.event_hash !== recalculatedHash) {
                    verificationResult.tamperedEntries.push(entry.id);
                    verificationResult.chainBreaks.push({
                        after: i,
                        reason: `Entry ${entry.id}: hash mismatch. Expected ${recalculatedHash}, got ${entry.event_hash}`,
                    });
                    verificationResult.isValid = false;
                }
                if (entry.event_hash === recalculatedHash && entry.previous_hash === expectedPrevHash) {
                    verificationResult.validEntries++;
                }
            }
            return verificationResult;
        }
        catch (err) {
            logger.error('Hash chain verification failed', {
                error: err instanceof Error ? err.message : String(err),
            });
            return {
                isValid: false,
                totalEntries: 0,
                validEntries: 0,
                tamperedEntries: [],
                missingEntries: [],
                chainBreaks: [],
                errors: [err instanceof Error ? err.message : String(err)],
            };
        }
    }
    /**
     * Generate a tamper detection report for compliance/audit purposes.
     */
    async generateTamperDetectionReport() {
        const verificationResult = await this.verifyChainIntegrity();
        let status = 'INTACT';
        const recommendations = [];
        if (verificationResult.chainBreaks.length > 0) {
            status = 'COMPROMISED';
            recommendations.push('Audit log chain integrity compromised. Investigate immediately.', 'Review all entries after first tamper point for unauthorized modifications.', 'Escalate to security team for forensic analysis.', `Affected records: ${verificationResult.tamperedEntries.join(', ')}`);
        }
        if (!verificationResult.isValid && verificationResult.errors.length > 0) {
            status = 'INCOMPLETE_CHAIN';
            recommendations.push('Audit log chain validation encountered errors.', 'Verify database integrity and availability.', 'Restore from known-good backup if chain corruption suspected.');
        }
        return {
            timestamp: new Date().toISOString(),
            status,
            verificationResult,
            firstTamperAt: verificationResult.tamperedEntries.length > 0 ? verificationResult.tamperedEntries[0] : undefined,
            affectedRecords: verificationResult.tamperedEntries.length > 0 ? verificationResult.tamperedEntries : undefined,
            recommendations,
        };
    }
    /**
     * Verify a specific audit log entry against its hash.
     * Useful for spot-checking individual records.
     */
    async verifySingleEntry(entryId) {
        try {
            const result = await this.db.query('SELECT event_hash, previous_hash FROM audit_logs WHERE id = $1', [entryId]);
            if (!result?.rows || result.rows.length === 0) {
                return { isValid: false, reason: `Entry ${entryId} not found` };
            }
            const entry = result.rows[0];
            const recalculatedHash = this._recalculateHash(entry);
            if (entry.event_hash !== recalculatedHash) {
                return { isValid: false, reason: `Hash mismatch: expected ${recalculatedHash}, got ${entry.event_hash}` };
            }
            return { isValid: true };
        }
        catch (err) {
            return { isValid: false, reason: err instanceof Error ? err.message : String(err) };
        }
    }
    /**
     * Recalculate hash for an entry.
     * Private method used for verification purposes.
     */
    _recalculateHash(entry) {
        const hash = createHash('sha256');
        const payload = JSON.stringify({
            u: entry.user_id,
            a: entry.action,
            r: entry.resource,
            prev: entry.previous_hash,
        });
        return hash.update(payload).digest('hex');
    }
}
// ── Singleton ─────────────────────────────────────────────────────────────────
let _instance = null;
/**
 * Initialize the hash chain verification service.
 */
export function initHashChainVerificationService(db) {
    _instance = new HashChainVerificationService(db);
    return _instance;
}
/**
 * Get the singleton instance.
 */
export function getHashChainVerificationService() {
    return _instance;
}
/**
 * Reset singleton — used in tests.
 */
export function resetHashChainVerificationService() {
    _instance = null;
}
//# sourceMappingURL=hash-chain-verification.js.map