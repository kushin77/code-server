const DEBUG_SESSION_API_BASE = '/api/debug-sessions';
async function requestJson(input, init) {
    const response = await fetch(input, {
        headers: {
            'Content-Type': 'application/json',
            ...(init?.headers ?? {}),
        },
        ...init,
    });
    if (!response.ok) {
        throw new Error(`Debug collaboration request failed with ${response.status}`);
    }
    return (await response.json());
}
export async function fetchDebugSession(sessionId) {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}`);
}
export async function createDebugSession(input) {
    return requestJson(DEBUG_SESSION_API_BASE, {
        method: 'POST',
        body: JSON.stringify(input),
    });
}
export async function joinDebugSession(sessionId, actor, role = 'collaborator') {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/join`, {
        method: 'POST',
        body: JSON.stringify({ actor, role }),
    });
}
export async function leaveDebugSession(sessionId, actor) {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/leave`, {
        method: 'POST',
        body: JSON.stringify({ actor }),
    });
}
export async function updateDebugBreakpoints(sessionId, input) {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/breakpoints`, {
        method: 'PUT',
        body: JSON.stringify(input),
    });
}
export async function updateDebugVariables(sessionId, input) {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/variables`, {
        method: 'PUT',
        body: JSON.stringify(input),
    });
}
export async function recordDebugStep(sessionId, input) {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/step`, {
        method: 'POST',
        body: JSON.stringify(input),
    });
}
export async function relayDebugProtocolMessage(sessionId, input) {
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/relay`, {
        method: 'POST',
        body: JSON.stringify(input),
    });
}
export async function fetchRelayedDebugMessages(sessionId, actor, sinceSequence = 0) {
    const params = new URLSearchParams({
        actor,
        since: String(Math.max(0, sinceSequence)),
    });
    return requestJson(`${DEBUG_SESSION_API_BASE}/${sessionId}/relay/messages?${params.toString()}`);
}
//# sourceMappingURL=debugCollaboration.js.map