const VALID_MODES = ['off', 'pilot', 'on'];
const DISABLED_CAPABILITIES = {
    tabs: false,
    switcher: false,
    persistence: false,
};
const DEFAULT_CAPABILITIES = {
    tabs: true,
    switcher: true,
    persistence: true,
};
function hashString(input) {
    let hash = 0;
    for (let index = 0; index < input.length; index += 1) {
        hash = (hash * 31 + input.charCodeAt(index)) >>> 0;
    }
    return hash;
}
function parseRolloutMode(rawMode) {
    if (rawMode === undefined) {
        return 'off';
    }
    return VALID_MODES.includes(rawMode)
        ? rawMode
        : null;
}
function normalizeCapabilities(capabilities) {
    return {
        tabs: capabilities?.tabs !== false,
        switcher: capabilities?.switcher !== false,
        persistence: capabilities?.persistence !== false,
    };
}
function mergeCapabilities(baseCapabilities, overrideCapabilities) {
    return {
        tabs: overrideCapabilities?.tabs ?? baseCapabilities.tabs,
        switcher: overrideCapabilities?.switcher ?? baseCapabilities.switcher,
        persistence: overrideCapabilities?.persistence ?? baseCapabilities.persistence,
    };
}
function parseRolloutConfig(rawConfig) {
    if (!rawConfig) {
        return null;
    }
    try {
        const parsedValue = JSON.parse(rawConfig);
        if (!parsedValue || typeof parsedValue !== 'object') {
            return null;
        }
        return parsedValue;
    }
    catch {
        return null;
    }
}
function buildDisabledDecision(rawMode) {
    if (rawMode === 'off') {
        return {
            mode: 'off',
            enabled: false,
            cohort: 'control',
            capabilities: DISABLED_CAPABILITIES,
            reason: 'multi-repo navigation rollout is disabled',
        };
    }
    return {
        mode: 'off',
        enabled: false,
        cohort: 'control',
        capabilities: DISABLED_CAPABILITIES,
        reason: rawMode
            ? `invalid multi-repo navigation mode '${rawMode}'`
            : 'multi-repo navigation mode is not configured',
    };
}
function buildPilotDecision(userId, normalizedPercentage, pilotCapabilities, controlCapabilities) {
    const hash = hashString(`multi-repo:${userId}`);
    const score = hash % 100;
    const enabled = score < normalizedPercentage;
    return {
        mode: 'pilot',
        enabled,
        cohort: enabled ? 'pilot' : 'control',
        capabilities: enabled ? pilotCapabilities : controlCapabilities,
        reason: enabled
            ? `user assigned to pilot cohort (${normalizedPercentage}% rollout)`
            : `user assigned to control cohort (${normalizedPercentage}% rollout)`,
    };
}
export function resolveMultiRepoRollout(userId) {
    const rawMode = import.meta.env.VITE_MULTI_REPO_NAVIGATION_MODE;
    const mode = parseRolloutMode(rawMode);
    const rawPercentage = import.meta.env.VITE_MULTI_REPO_PILOT_PERCENTAGE;
    const parsedPercentage = Number(rawPercentage ?? '25');
    const config = parseRolloutConfig(import.meta.env.VITE_MULTI_REPO_REMOTE_CONFIG);
    const defaultCapabilities = mergeCapabilities(DEFAULT_CAPABILITIES, normalizeCapabilities(config?.defaultCapabilities));
    if (!mode) {
        return buildDisabledDecision(rawMode);
    }
    if (mode === 'off') {
        return buildDisabledDecision(rawMode);
    }
    if (mode === 'on') {
        const fullCapabilities = mergeCapabilities(defaultCapabilities, normalizeCapabilities(config?.cohortCapabilities?.full));
        return {
            mode,
            enabled: true,
            cohort: 'full',
            capabilities: fullCapabilities,
            reason: 'multi-repo navigation is fully enabled',
        };
    }
    if (!userId) {
        return {
            mode,
            enabled: false,
            cohort: 'control',
            capabilities: DISABLED_CAPABILITIES,
            reason: 'pilot mode requires a user identity for stable assignment',
        };
    }
    const normalizedPercentage = Number.isFinite(parsedPercentage)
        ? Math.min(100, Math.max(0, parsedPercentage))
        : 25;
    const pilotCapabilities = mergeCapabilities(defaultCapabilities, normalizeCapabilities(config?.cohortCapabilities?.pilot));
    const controlCapabilities = mergeCapabilities(defaultCapabilities, normalizeCapabilities(config?.cohortCapabilities?.control));
    return buildPilotDecision(userId, normalizedPercentage, pilotCapabilities, controlCapabilities);
}
//# sourceMappingURL=multiRepoRollout.js.map