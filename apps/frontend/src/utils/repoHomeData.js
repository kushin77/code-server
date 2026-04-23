export const REPO_HOME_CACHE_KEY = 'repo-home:snapshot';
const DEFAULT_REFRESH_INTERVAL_MS = 30000;
const MIN_REFRESH_INTERVAL_MS = 5000;
const MAX_REFRESH_INTERVAL_MS = 300000;
function clampRefreshInterval(value) {
    return Math.min(MAX_REFRESH_INTERVAL_MS, Math.max(MIN_REFRESH_INTERVAL_MS, value));
}
export function resolveRepoStatusRefreshIntervalMs(rawValue) {
    const parsedValue = Number(rawValue ?? import.meta.env.VITE_MULTI_REPO_STATUS_REFRESH_MS ?? DEFAULT_REFRESH_INTERVAL_MS);
    if (!Number.isFinite(parsedValue)) {
        return DEFAULT_REFRESH_INTERVAL_MS;
    }
    return clampRefreshInterval(parsedValue);
}
function buildRepoLinks(repoSlug) {
    return {
        workspace: '/',
        pullRequests: `https://github.com/${repoSlug}/pulls`,
        ci: `https://github.com/${repoSlug}/actions`,
        issues: `https://github.com/${repoSlug}/issues`,
        runbook: `https://github.com/${repoSlug}/blob/main/README.md`,
    };
}
export function buildSeedRepoHomeCards(now = Date.now()) {
    return [
        {
            id: 'portal-main',
            label: 'Portal main',
            repoSlug: 'kushin77/code-server',
            description: 'Primary repo surface for the portal and RBAC dashboard.',
            favorite: true,
            sharedSet: 'Platform core',
            status: {
                branch: 'main',
                dirty: false,
                ciStatus: 'passing',
                lastActivityAt: now - 5 * 60 * 1000,
            },
            links: buildRepoLinks('kushin77/code-server'),
        },
        {
            id: 'docs-review',
            label: 'Docs review',
            repoSlug: 'kushin77/platform-docs',
            description: 'Runbook and governance doc set used during release prep.',
            favorite: true,
            sharedSet: 'Release readiness',
            status: {
                branch: 'docs-sync',
                dirty: true,
                ciStatus: 'running',
                lastActivityAt: now - 18 * 60 * 1000,
            },
            links: buildRepoLinks('kushin77/platform-docs'),
        },
        {
            id: 'ops-control',
            label: 'Ops control',
            repoSlug: 'kushin77/ops-control',
            description: 'Operational automation, redeploy gates, and failover controls.',
            favorite: true,
            sharedSet: 'Operations',
            status: {
                branch: 'release-control',
                dirty: false,
                ciStatus: 'failing',
                lastActivityAt: now - 42 * 60 * 1000,
            },
            errorHint: {
                code: 'ci_unavailable',
                title: 'Certification lane needs operator attention',
                remediation: 'Review the latest certification run and clear the blocking workflow before promoting this repo.',
            },
            links: buildRepoLinks('kushin77/ops-control'),
        },
        {
            id: 'dev-sandbox',
            label: 'Dev sandbox',
            repoSlug: 'kushin77/dev-sandbox',
            description: 'Experimental feature branch workspace for pilot navigation flows.',
            favorite: false,
            sharedSet: 'Pilot cohort',
            status: {
                branch: 'feature/multi-repo',
                dirty: true,
                ciStatus: 'passing',
                lastActivityAt: now - 8 * 60 * 1000,
            },
            links: buildRepoLinks('kushin77/dev-sandbox'),
        },
        {
            id: 'security-lab',
            label: 'Security lab',
            repoSlug: 'kushin77/security-lab',
            description: 'Security hardening workspace with stricter repo access controls.',
            favorite: false,
            sharedSet: 'Security review',
            status: {
                branch: 'hardening',
                dirty: false,
                ciStatus: 'blocked',
                lastActivityAt: now - 90 * 60 * 1000,
            },
            errorHint: {
                code: 'auth',
                title: 'Repository access needs renewed credentials',
                remediation: 'Re-authenticate GitHub access for this repo before attempting switch or pull actions.',
            },
            links: buildRepoLinks('kushin77/security-lab'),
        },
    ];
}
export function sortRepoHomeCards(cards) {
    return [...cards].sort((left, right) => {
        if (left.favorite !== right.favorite) {
            return left.favorite ? -1 : 1;
        }
        if (left.sharedSet && !right.sharedSet) {
            return -1;
        }
        if (!left.sharedSet && right.sharedSet) {
            return 1;
        }
        return left.label.localeCompare(right.label);
    });
}
export function createDefaultRepoHomeSnapshot(now = Date.now()) {
    return {
        cards: sortRepoHomeCards(buildSeedRepoHomeCards(now)),
        fetchedAt: now,
        refreshIntervalMs: resolveRepoStatusRefreshIntervalMs(),
    };
}
function isValidRepoCard(value) {
    if (!value || typeof value !== 'object') {
        return false;
    }
    const candidate = value;
    return (typeof candidate.id === 'string' &&
        typeof candidate.label === 'string' &&
        typeof candidate.repoSlug === 'string' &&
        typeof candidate.description === 'string' &&
        typeof candidate.favorite === 'boolean' &&
        !!candidate.status &&
        typeof candidate.status.branch === 'string' &&
        typeof candidate.status.dirty === 'boolean' &&
        typeof candidate.status.ciStatus === 'string' &&
        typeof candidate.status.lastActivityAt === 'number' &&
        !!candidate.links &&
        typeof candidate.links.workspace === 'string' &&
        typeof candidate.links.pullRequests === 'string' &&
        typeof candidate.links.ci === 'string' &&
        typeof candidate.links.issues === 'string' &&
        typeof candidate.links.runbook === 'string');
}
export function readRepoHomeSnapshot(storage) {
    if (!storage) {
        return null;
    }
    try {
        const rawValue = storage.getItem(REPO_HOME_CACHE_KEY);
        if (!rawValue) {
            return null;
        }
        const parsedValue = JSON.parse(rawValue);
        if (!Array.isArray(parsedValue.cards) ||
            !parsedValue.cards.every((card) => isValidRepoCard(card)) ||
            typeof parsedValue.fetchedAt !== 'number' ||
            typeof parsedValue.refreshIntervalMs !== 'number') {
            return null;
        }
        return {
            cards: sortRepoHomeCards(parsedValue.cards),
            fetchedAt: parsedValue.fetchedAt,
            refreshIntervalMs: clampRefreshInterval(parsedValue.refreshIntervalMs),
        };
    }
    catch {
        return null;
    }
}
export function writeRepoHomeSnapshot(storage, snapshot) {
    if (!storage) {
        return;
    }
    storage.setItem(REPO_HOME_CACHE_KEY, JSON.stringify({
        ...snapshot,
        cards: sortRepoHomeCards(snapshot.cards),
        refreshIntervalMs: clampRefreshInterval(snapshot.refreshIntervalMs),
    }));
}
export function refreshRepoHomeSnapshot(snapshot, now = Date.now()) {
    return {
        ...snapshot,
        cards: sortRepoHomeCards(snapshot.cards),
        fetchedAt: now,
    };
}
export function formatRepoHomeRefreshLabel(fetchedAt, now = Date.now()) {
    const ageMs = Math.max(0, now - fetchedAt);
    const ageSeconds = Math.round(ageMs / 1000);
    if (ageSeconds < 60) {
        return `${ageSeconds}s ago`;
    }
    const ageMinutes = Math.round(ageSeconds / 60);
    if (ageMinutes < 60) {
        return `${ageMinutes}m ago`;
    }
    const ageHours = Math.round(ageMinutes / 60);
    return `${ageHours}h ago`;
}
export function formatRepoLastActivity(lastActivityAt, now = Date.now()) {
    const ageMs = Math.max(0, now - lastActivityAt);
    const ageMinutes = Math.round(ageMs / 60000);
    if (ageMinutes < 1) {
        return 'active just now';
    }
    if (ageMinutes < 60) {
        return `active ${ageMinutes}m ago`;
    }
    const ageHours = Math.round(ageMinutes / 60);
    return `active ${ageHours}h ago`;
}
export function getRepoCardTone(ciStatus) {
    switch (ciStatus) {
        case 'passing':
            return 'emerald';
        case 'running':
            return 'sky';
        case 'failing':
            return 'rose';
        case 'blocked':
            return 'amber';
        default:
            return 'slate';
    }
}
export function buildRepoCardActions(card, policy, activeRepoId) {
    const isActive = card.id === activeRepoId;
    const isAdminOrDeveloper = policy.label === 'Admin' || policy.label === 'Developer';
    const isAuditor = policy.label === 'Auditor';
    const blockedByAuth = card.errorHint?.code === 'auth';
    return [
        {
            id: 'open',
            label: isActive ? 'Open active' : 'Open',
            disabled: isAuditor,
            reason: isAuditor ? 'Audit policy allows runbook access only for this surface' : undefined,
        },
        {
            id: 'switch',
            label: isActive ? 'Active' : 'Switch',
            disabled: isActive || !policy.canSwitchWorkspace || blockedByAuth,
            reason: isActive
                ? 'Already focused on this workspace'
                : isAuditor
                    ? 'Audit policy allows runbook access only for this surface'
                    : blockedByAuth
                        ? card.errorHint?.remediation
                        : !policy.canSwitchWorkspace
                            ? `Policy ${policy.label} does not allow repo switching`
                            : undefined,
        },
        {
            id: 'pull',
            label: 'Pull',
            disabled: !isAdminOrDeveloper || blockedByAuth,
            reason: blockedByAuth
                ? card.errorHint?.remediation
                : !isAdminOrDeveloper
                    ? 'Only developer-capable roles can trigger pull actions'
                    : undefined,
        },
        {
            id: 'pullRequests',
            label: 'PRs',
            disabled: isAuditor,
            reason: isAuditor ? 'Audit policy keeps external repo actions disabled on the home view' : undefined,
            external: true,
        },
        {
            id: 'issues',
            label: 'Issues',
            disabled: isAuditor,
            reason: isAuditor ? 'Audit policy keeps issue navigation disabled on the home view' : undefined,
            external: true,
        },
        {
            id: 'runbook',
            label: 'Runbook',
            disabled: false,
            external: true,
        },
    ];
}
//# sourceMappingURL=repoHomeData.js.map