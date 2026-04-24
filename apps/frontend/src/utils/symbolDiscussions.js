// @file        apps/frontend/src/utils/symbolDiscussions.ts
// @module      utils/symbol-discussions
// @description Frontend helpers for inline symbol discussion lookups
const SYMBOL_DISCUSSIONS_API_BASE = '/api/symbol-discussions';
async function requestJson(input, init) {
    const response = await fetch(input, {
        headers: {
            'Content-Type': 'application/json',
            ...(init?.headers ?? {}),
        },
        ...init,
    });
    if (!response.ok) {
        throw new Error(`Symbol discussion request failed with ${response.status}`);
    }
    return (await response.json());
}
export async function fetchSymbolDiscussionsByLocation(filePath, lineNumber) {
    const params = new URLSearchParams({ filePath });
    if (lineNumber !== undefined && Number.isFinite(lineNumber)) {
        params.set('lineNumber', String(Math.max(1, Math.trunc(lineNumber))));
    }
    return requestJson(`${SYMBOL_DISCUSSIONS_API_BASE}/location?${params.toString()}`);
}
//# sourceMappingURL=symbolDiscussions.js.map