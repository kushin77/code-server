import { createHash } from 'node:crypto'

export type SessionProvenanceVerificationResult = 'verified' | 'rejected'

export interface SessionProvenanceManifest {
  manifestVersion: 'v1'
  imageDigest: string
  attestationRef: string
  signerIdentity: string
  verifiedAt: string
  verificationResult: SessionProvenanceVerificationResult
  policyVersion: string
  freshnessHours: number
  sessionFingerprint: string
}

export interface SessionProvenanceRuntimeConfig {
  provenanceImageDigest: string
  provenanceAttestationRef: string
  provenanceSignerIdentity: string
  provenanceVerifiedAt: string
  provenancePolicyVersion: string
  provenanceFreshnessHours: number
  provenanceVerificationResult?: string
}

export interface SessionLaunchProvenanceInput {
  attestationRef: string
  signerIdentity: string
  verifiedAt: string
  policyVersion: string
  freshnessHours: number
  verificationResult?: SessionProvenanceVerificationResult
}

const computeSessionProvenanceFingerprint = (
  manifest: Omit<SessionProvenanceManifest, 'sessionFingerprint'>,
): string => {
  const payload = {
    manifestVersion: manifest.manifestVersion,
    imageDigest: manifest.imageDigest,
    attestationRef: manifest.attestationRef,
    signerIdentity: manifest.signerIdentity,
    verifiedAt: manifest.verifiedAt,
    verificationResult: manifest.verificationResult,
    policyVersion: manifest.policyVersion,
    freshnessHours: manifest.freshnessHours,
  }

  return `sha256:${createHash('sha256').update(JSON.stringify(payload)).digest('hex')}`
}

export class SessionProvenancePolicyError extends Error {
  readonly statusCode: number
  readonly policyCode: string

  constructor(statusCode: number, policyCode: string, message: string) {
    super(message)
    this.statusCode = statusCode
    this.policyCode = policyCode
  }
}

const isDigestPinnedImage = (imageDigest: string): boolean => /^sha256:[a-f0-9]{64}$/i.test(imageDigest)

const parseVerifiedAt = (verifiedAt: string): Date => {
  const parsed = new Date(verifiedAt)
  if (Number.isNaN(parsed.getTime())) {
    throw new SessionProvenancePolicyError(422, 'provenance_verified_at_invalid', 'SESSION_PROVENANCE_VERIFIED_AT must be an ISO-8601 timestamp')
  }

  return parsed
}

export const buildSessionProvenanceManifest = (
  config: SessionProvenanceRuntimeConfig,
): SessionProvenanceManifest => {
  const imageDigest = config.provenanceImageDigest.trim()
  const attestationRef = config.provenanceAttestationRef.trim()
  const signerIdentity = config.provenanceSignerIdentity.trim()
  const policyVersion = config.provenancePolicyVersion.trim()
  const freshnessHours = config.provenanceFreshnessHours
  const verificationResult = (config.provenanceVerificationResult ?? 'verified').trim().toLowerCase()

  if (!isDigestPinnedImage(imageDigest)) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_image_not_pinned',
      'CODE_SERVER_IMAGE_ID must be a sha256 digest-pinned image reference',
    )
  }

  if (!attestationRef) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_attestation_missing',
      'SESSION_PROVENANCE_ATTESTATION_REF is required',
    )
  }

  if (!signerIdentity) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_signer_missing',
      'SESSION_PROVENANCE_SIGNER_IDENTITY is required',
    )
  }

  if (!policyVersion) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_policy_missing',
      'SESSION_PROVENANCE_POLICY_VERSION is required',
    )
  }

  if (!Number.isInteger(freshnessHours) || freshnessHours < 1) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_freshness_invalid',
      'SESSION_PROVENANCE_FRESHNESS_HOURS must be a positive integer',
    )
  }

  if (verificationResult !== 'verified') {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_not_verified',
      'Launch provenance verification must be verified before session launch',
    )
  }

  const verifiedAt = parseVerifiedAt(config.provenanceVerifiedAt.trim())
  const expiresAt = new Date(verifiedAt.getTime() + freshnessHours * 60 * 60 * 1000)
  if (expiresAt.getTime() <= Date.now()) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_stale',
      'Launch provenance verification has expired and must be refreshed before session launch',
    )
  }

  const manifestWithoutFingerprint: Omit<SessionProvenanceManifest, 'sessionFingerprint'> = {
    manifestVersion: 'v1',
    imageDigest,
    attestationRef,
    signerIdentity,
    verifiedAt: verifiedAt.toISOString(),
    verificationResult: 'verified',
    policyVersion,
    freshnessHours,
  }

  return {
    ...manifestWithoutFingerprint,
    sessionFingerprint: computeSessionProvenanceFingerprint(manifestWithoutFingerprint),
  }
}

export const normalizeSessionProvenanceManifest = (
  manifest: Partial<SessionProvenanceManifest> | null | undefined,
): SessionProvenanceManifest | null => {
  if (!manifest) {
    return null
  }

  const imageDigest = typeof manifest.imageDigest === 'string' ? manifest.imageDigest.trim() : ''
  const attestationRef = typeof manifest.attestationRef === 'string' ? manifest.attestationRef.trim() : ''
  const signerIdentity = typeof manifest.signerIdentity === 'string' ? manifest.signerIdentity.trim() : ''
  const verifiedAt = typeof manifest.verifiedAt === 'string' ? manifest.verifiedAt.trim() : ''
  const policyVersion = typeof manifest.policyVersion === 'string' ? manifest.policyVersion.trim() : ''
  const freshnessHours = Number(manifest.freshnessHours)
  const verificationResult = manifest.verificationResult === 'rejected' ? 'rejected' : 'verified'
  const sessionFingerprint = typeof manifest.sessionFingerprint === 'string' ? manifest.sessionFingerprint.trim() : ''

  if (!imageDigest || !attestationRef || !signerIdentity || !verifiedAt || !policyVersion) {
    return null
  }

  const normalizedWithoutFingerprint: Omit<SessionProvenanceManifest, 'sessionFingerprint'> = {
    manifestVersion: 'v1' as const,
    imageDigest,
    attestationRef,
    signerIdentity,
    verifiedAt,
    verificationResult,
    policyVersion,
    freshnessHours: Number.isInteger(freshnessHours) && freshnessHours > 0 ? freshnessHours : 24,
  }

  const expectedFingerprint = computeSessionProvenanceFingerprint(normalizedWithoutFingerprint)

  return {
    ...normalizedWithoutFingerprint,
    sessionFingerprint: expectedFingerprint,
  }
}

export const validateSessionProvenanceManifest = (
  manifest: Partial<SessionProvenanceManifest> | null | undefined,
  expectedImageDigest: string,
): SessionProvenanceManifest => {
  const normalized = normalizeSessionProvenanceManifest(manifest)

  if (!normalized) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_manifest_invalid',
      'Session provenance manifest is missing required fields',
    )
  }

  if (normalized.manifestVersion !== 'v1') {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_manifest_version_unsupported',
      'Session provenance manifest version is unsupported',
    )
  }

  if (!isDigestPinnedImage(expectedImageDigest.trim())) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_image_not_pinned',
      'Trusted launch image must be pinned to a sha256 digest',
    )
  }

  if (normalized.imageDigest !== expectedImageDigest.trim()) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_image_mismatch',
      'Session provenance manifest image digest does not match the trusted launch image digest',
    )
  }

  if (normalized.verificationResult !== 'verified') {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_not_verified',
      'Launch provenance verification must be verified before session launch',
    )
  }

  const verifiedAt = parseVerifiedAt(normalized.verifiedAt)
  const expiresAt = new Date(verifiedAt.getTime() + normalized.freshnessHours * 60 * 60 * 1000)

  if (expiresAt.getTime() <= Date.now()) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_stale',
      'Launch provenance verification has expired and must be refreshed before session launch',
    )
  }

  const expectedFingerprint = computeSessionProvenanceFingerprint(normalized)
  const providedFingerprint = typeof manifest?.sessionFingerprint === 'string' ? manifest.sessionFingerprint.trim() : ''

  if (providedFingerprint && providedFingerprint !== expectedFingerprint) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_fingerprint_mismatch',
      'Session provenance fingerprint does not match the canonical manifest fingerprint',
    )
  }

  if (normalized.sessionFingerprint !== expectedFingerprint) {
    throw new SessionProvenancePolicyError(
      422,
      'provenance_fingerprint_mismatch',
      'Session provenance fingerprint does not match the canonical manifest fingerprint',
    )
  }

  return normalized
}

export const resolveSessionProvenanceManifest = (
  config: SessionProvenanceRuntimeConfig,
  manifest?: Partial<SessionProvenanceManifest> | null,
): SessionProvenanceManifest => {
  if (manifest) {
    return validateSessionProvenanceManifest(manifest, config.provenanceImageDigest)
  }

  return buildSessionProvenanceManifest(config)
}
