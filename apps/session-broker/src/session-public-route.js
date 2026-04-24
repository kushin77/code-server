const DEFAULT_SESSION_PUBLIC_BASE_URL = 'https://dev.kushnir.cloud';
const DEFAULT_SESSION_PUBLIC_ROUTE_PREFIX = '/s';
const normalizeBaseUrl = (baseUrl) => baseUrl.trim().replace(/\/+$/, '');
const normalizeRoutePrefix = (routePrefix) => {
    const trimmed = routePrefix.trim();
    if (trimmed === '' || trimmed === '/') {
        return '';
    }
    const withoutLeadingSlash = trimmed.replace(/^\/+/, '');
    return `/${withoutLeadingSlash.replace(/\/+$/, '')}`;
};
export const buildSessionPublicUrl = (baseUrl = DEFAULT_SESSION_PUBLIC_BASE_URL, sessionId, routePrefix = DEFAULT_SESSION_PUBLIC_ROUTE_PREFIX) => {
    const normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    const normalizedRoutePrefix = normalizeRoutePrefix(routePrefix);
    return `${normalizedBaseUrl}${normalizedRoutePrefix}/${encodeURIComponent(sessionId)}`;
};
export const stripSessionPublicRoutePrefix = (originalUrl, sessionId, routePrefix = DEFAULT_SESSION_PUBLIC_ROUTE_PREFIX) => {
    const parsedUrl = new URL(originalUrl, 'http://localhost');
    const normalizedRoutePrefix = normalizeRoutePrefix(routePrefix);
    const encodedSessionId = encodeURIComponent(sessionId);
    const expectedPrefix = `${normalizedRoutePrefix}/${encodedSessionId}`;
    let pathname = parsedUrl.pathname;
    if (pathname === expectedPrefix) {
        pathname = '/';
    }
    else if (pathname.startsWith(`${expectedPrefix}/`)) {
        pathname = pathname.slice(expectedPrefix.length);
    }
    if (!pathname.startsWith('/')) {
        pathname = `/${pathname}`;
    }
    return `${pathname}${parsedUrl.search}`;
};
//# sourceMappingURL=session-public-route.js.map