export const APPROVED_SESSION_DATA_PROFILES = ['synthetic', 'masked', 'redacted'];
export const DEFAULT_SESSION_DATA_PROFILE = 'synthetic';
const APPROVED_SESSION_DATA_PROFILE_SET = new Set(APPROVED_SESSION_DATA_PROFILES);
export function normalizeSessionDataProfile(value) {
    if (!value) {
        return null;
    }
    const normalized = value.trim().toLowerCase();
    return APPROVED_SESSION_DATA_PROFILE_SET.has(normalized)
        ? normalized
        : null;
}
export function isApprovedSessionDataProfile(value) {
    return normalizeSessionDataProfile(value) !== null;
}
//# sourceMappingURL=session-data-profile.js.map