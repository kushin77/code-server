/**
 * Zero-Trust Authenticator
 *
 * Implements continuous cryptographic identity verification with:
 * - Device fingerprinting and trust scoring
 * - Multi-factor identity validation
 * - Continuous re-authentication
 * - Risk-based access control
 * - Certificate pinning and token rotation
 */
export interface DeviceSignature {
    deviceId: string;
    fingerprint: string;
    osType: string;
    osVersion: string;
    browserVersion?: string;
    trustScore: number;
    lastSeen: Date;
    locations: GeographicLocation[];
}
export interface GeographicLocation {
    latitude: number;
    longitude: number;
    country: string;
    city: string;
    timestamp: Date;
    riskScore: number;
}
export interface IdentityToken {
    userId: string;
    tokenId: string;
    issuedAt: Date;
    expiresAt: Date;
    scopes: string[];
    deviceId: string;
    riskLevel: 'low' | 'medium' | 'high' | 'critical';
    mfaVerified: boolean;
    trustChain: string[];
}
export interface AuthenticationContext {
    userId: string;
    deviceId: string;
    timestamp: Date;
    requestHash: string;
    ipAddress: string;
    userAgent: string;
    location?: GeographicLocation;
    previousAuthSession?: string;
}
export interface AuthenticationResult {
    success: boolean;
    token?: IdentityToken;
    riskScore: number;
    requiresMFA: boolean;
    reason?: string;
    trustDecision: 'allow' | 'challenge' | 'deny';
}
/**
 * ZeroTrustAuthenticator - Continuous cryptographic identity verification
 *
 * Implements zero-trust principles:
 * - Never trust, always verify
 * - Assume compromise
 * - Continuous authentication
 * - Risk-adaptive access control
 */
export declare class ZeroTrustAuthenticator {
    private devices;
    private tokens;
    private authHistory;
    private readonly maxHistorySize;
    private readonly tokenRotationInterval;
    private readonly riskThreshold;
    private readonly mfaRequiredThreshold;
    constructor();
    /**
     * Initialize default security policies
     */
    private initializeDefaultPolicies;
    /**
     * Register a new device with trust baseline
     */
    registerDevice(signature: DeviceSignature): string;
    /**
     * Calculate device fingerprint from characteristics
     * Returns SHA-256 hash for comparison
     */
    calculateDeviceFingerprint(osType: string, osVersion: string, browserVersion?: string, additionalFeatures?: Record<string, string>): string;
    /**
     * Detect impossible travel attacks
     * Returns risk score based on geographic distance and time delta
     */
    private detectImpossibleTravel;
    /**
     * Authenticate user with continuous verification
     * Implements zero-trust continuous authentication
     */
    authenticate(context: AuthenticationContext, credential: string): Promise<AuthenticationResult>;
    /**
     * Verify an existing token (validation)
     */
    verifyToken(tokenId: string): {
        valid: boolean;
        token?: IdentityToken;
        reason?: string;
    };
    /**
     * Rotate token (forces re-authentication)
     */
    rotateToken(oldTokenId: string): IdentityToken | null;
    /**
     * Get device trust status
     */
    getDeviceTrust(deviceId: string): {
        trusted: boolean;
        trustScore: number;
        reason: string;
    };
    /**
     * Get authentication history statistics
     */
    getAuthenticationStats(): {
        totalAttempts: number;
        successfulAuthentications: number;
        failedAuthentications: number;
        challengedAuthentications: number;
        averageRiskScore: number;
        mfaRequiredCount: number;
    };
    /**
     * Revoke all tokens for a user (e.g., on logout or account compromise)
     */
    revokeUserTokens(userId: string): number;
    /**
     * Get active tokens for user
     */
    getActiveTokens(userId: string): IdentityToken[];
}
//# sourceMappingURL=ZeroTrustAuthenticator.d.ts.map
