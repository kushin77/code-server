// @file        apps/frontend/src/utils/voiceChannel.ts
// @module      utils/voice-channel
// @description Frontend helpers for voice channel sessions and stats
const VOICE_CHANNEL_API_BASE = '/api/voice';
async function requestJson(input, authToken, init) {
    const response = await fetch(input, {
        headers: {
            'Content-Type': 'application/json',
            ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
            ...(init?.headers ?? {}),
        },
        ...init,
    });
    if (!response.ok) {
        throw new Error(`Voice channel request failed with ${response.status}`);
    }
    return (await response.json());
}
export async function createVoiceSession(workspaceId, authToken) {
    return requestJson(`${VOICE_CHANNEL_API_BASE}/sessions`, authToken, {
        method: 'POST',
        body: JSON.stringify({ workspaceId }),
    });
}
export async function joinVoiceSession(sessionId, authToken) {
    return requestJson(`${VOICE_CHANNEL_API_BASE}/sessions/${encodeURIComponent(sessionId)}/join`, authToken, {
        method: 'POST',
    });
}
export async function leaveVoiceSession(sessionId, authToken) {
    return requestJson(`${VOICE_CHANNEL_API_BASE}/sessions/${encodeURIComponent(sessionId)}/leave`, authToken, {
        method: 'POST',
    });
}
export async function fetchVoiceSession(sessionId, authToken) {
    return requestJson(`${VOICE_CHANNEL_API_BASE}/sessions/${encodeURIComponent(sessionId)}`, authToken);
}
export async function fetchWorkspaceVoiceSessions(workspaceId, authToken) {
    return requestJson(`${VOICE_CHANNEL_API_BASE}/workspaces/${encodeURIComponent(workspaceId)}/sessions`, authToken);
}
export async function fetchVoiceStats(authToken) {
    return requestJson(`${VOICE_CHANNEL_API_BASE}/stats`, authToken);
}
//# sourceMappingURL=voiceChannel.js.map