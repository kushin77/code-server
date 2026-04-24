import { describe, expect, it } from 'vitest'
import {
  buildSessionProvenanceManifest,
  normalizeSessionProvenanceManifest,
  resolveSessionProvenanceManifest,
  SessionProvenancePolicyError,
  validateSessionProvenanceManifest,
} from './session-provenance.js'

describe('session provenance contract', () => {
  const baseConfig = {
    provenanceImageDigest: 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    provenanceAttestationRef: 'rekor://attestations/session-broker@v1',
    provenanceSignerIdentity: 'github.com/kushin77/code-server/.github/workflows/verified-build.yml',
    provenanceVerifiedAt: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
    provenancePolicyVersion: 'v1.0.0',
    provenanceFreshnessHours: 24,
    provenanceVerificationResult: 'verified',
  }

  it('builds a normalized provenance manifest for a pinned image', () => {
    const manifest = buildSessionProvenanceManifest(baseConfig)

    expect(manifest).toMatchObject({
      manifestVersion: 'v1',
      imageDigest: baseConfig.provenanceImageDigest,
      attestationRef: baseConfig.provenanceAttestationRef,
      signerIdentity: baseConfig.provenanceSignerIdentity,
      verifiedAt: baseConfig.provenanceVerifiedAt,
      verificationResult: 'verified',
      policyVersion: baseConfig.provenancePolicyVersion,
      freshnessHours: 24,
    })
    expect(manifest.sessionFingerprint).toMatch(/^sha256:[a-f0-9]{64}$/i)
  })

  it('resolves persisted provenance when one is supplied', () => {
    const manifest = resolveSessionProvenanceManifest(baseConfig, {
      manifestVersion: 'v1',
      imageDigest: baseConfig.provenanceImageDigest,
      attestationRef: baseConfig.provenanceAttestationRef,
      signerIdentity: baseConfig.provenanceSignerIdentity,
      verifiedAt: baseConfig.provenanceVerifiedAt,
      verificationResult: 'verified',
      policyVersion: baseConfig.provenancePolicyVersion,
      freshnessHours: 24,
    })

    expect(manifest.imageDigest).toBe(baseConfig.provenanceImageDigest)
    expect(manifest.verificationResult).toBe('verified')
    expect(manifest.sessionFingerprint).toMatch(/^sha256:[a-f0-9]{64}$/i)
  })

  it('fails closed when the image is not digest pinned', () => {
    expect(() => buildSessionProvenanceManifest({
      ...baseConfig,
      provenanceImageDigest: 'code-server:latest',
    })).toThrow(SessionProvenancePolicyError)
  })

  it('fails closed when provenance is stale', () => {
    expect(() => buildSessionProvenanceManifest({
      ...baseConfig,
      provenanceVerifiedAt: new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString(),
      provenanceFreshnessHours: 24,
    })).toThrow('expired')
  })

  it('fails closed when a persisted manifest image digest does not match the trusted launch image', () => {
    expect(() => validateSessionProvenanceManifest({
      manifestVersion: 'v1',
      imageDigest: 'sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      attestationRef: baseConfig.provenanceAttestationRef,
      signerIdentity: baseConfig.provenanceSignerIdentity,
      verifiedAt: baseConfig.provenanceVerifiedAt,
      verificationResult: 'verified',
      policyVersion: baseConfig.provenancePolicyVersion,
      freshnessHours: 24,
    }, baseConfig.provenanceImageDigest)).toThrow(SessionProvenancePolicyError)
  })

  it('returns null for incomplete persisted provenance manifests', () => {
    expect(normalizeSessionProvenanceManifest(null)).toBeNull()
    expect(normalizeSessionProvenanceManifest({
      imageDigest: baseConfig.provenanceImageDigest,
      attestationRef: '',
      signerIdentity: baseConfig.provenanceSignerIdentity,
      verifiedAt: baseConfig.provenanceVerifiedAt,
      verificationResult: 'verified',
      policyVersion: baseConfig.provenancePolicyVersion,
      freshnessHours: 24,
      manifestVersion: 'v1',
    })).toBeNull()
  })

  it('derives a stable session fingerprint when one is missing', () => {
    const normalized = normalizeSessionProvenanceManifest({
      manifestVersion: 'v1',
      imageDigest: baseConfig.provenanceImageDigest,
      attestationRef: baseConfig.provenanceAttestationRef,
      signerIdentity: baseConfig.provenanceSignerIdentity,
      verifiedAt: baseConfig.provenanceVerifiedAt,
      verificationResult: 'verified',
      policyVersion: baseConfig.provenancePolicyVersion,
      freshnessHours: 24,
    })

    expect(normalized?.sessionFingerprint).toMatch(/^sha256:[a-f0-9]{64}$/i)
  })

  it('rejects replay manifests with mismatched fingerprints', () => {
    expect(() => validateSessionProvenanceManifest({
      manifestVersion: 'v1',
      imageDigest: baseConfig.provenanceImageDigest,
      attestationRef: baseConfig.provenanceAttestationRef,
      signerIdentity: baseConfig.provenanceSignerIdentity,
      verifiedAt: baseConfig.provenanceVerifiedAt,
      verificationResult: 'verified',
      policyVersion: baseConfig.provenancePolicyVersion,
      freshnessHours: 24,
      sessionFingerprint: `sha256:${'b'.repeat(64)}`,
    }, baseConfig.provenanceImageDigest)).toThrow('fingerprint')
  })
})
