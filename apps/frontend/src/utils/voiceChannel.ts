// @file        apps/frontend/src/utils/voiceChannel.ts
// @module      utils/voice-channel
// @description Frontend helpers for voice channel sessions and stats

export type VoiceSessionStatus = 'active' | 'idle' | 'ended'

export type VoiceSession = {
  sessionId: string
  workspaceId: string
  userId: string
  liveKitToken: string
  liveKitRoomName: string
  startedAt: number
  participantCount: number
  status: VoiceSessionStatus
}

export type VoiceParticipant = {
  userId: string
  username: string
  displayName: string
  status: 'connected' | 'disconnected' | 'muted' | 'deafened'
  joinedAt: number
  audioLatencyMs?: number
  audioQualityScore?: number
}

export type VoiceStats = {
  activeSessionsCount: number
  totalParticipants: number
  averageLatencyMs: number
  audioQualityP50: number
  audioQualityP95: number
  noiseReductionEnabled: boolean
  timestamp: number
}

export type VoiceSessionCreateResponse = {
  session: VoiceSession
  token: string
  liveKitUrl: string
}

export type VoiceSessionJoinResponse = VoiceSessionCreateResponse

export type VoiceWorkspaceSessionsResponse = {
  sessions: VoiceSession[]
  count: number
}

export type VoiceSessionDetailsResponse = {
  session: VoiceSession
  participants: VoiceParticipant[]
}

const VOICE_CHANNEL_API_BASE = '/api/voice'

async function requestJson<T>(input: RequestInfo | URL, authToken: string | null, init?: RequestInit): Promise<T> {
  const response = await fetch(input, {
    headers: {
      'Content-Type': 'application/json',
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (!response.ok) {
    throw new Error(`Voice channel request failed with ${response.status}`)
  }

  return (await response.json()) as T
}

export async function createVoiceSession(workspaceId: string, authToken: string | null): Promise<VoiceSessionCreateResponse> {
  return requestJson<VoiceSessionCreateResponse>(`${VOICE_CHANNEL_API_BASE}/sessions`, authToken, {
    method: 'POST',
    body: JSON.stringify({ workspaceId }),
  })
}

export async function joinVoiceSession(sessionId: string, authToken: string | null): Promise<VoiceSessionJoinResponse> {
  return requestJson<VoiceSessionJoinResponse>(`${VOICE_CHANNEL_API_BASE}/sessions/${encodeURIComponent(sessionId)}/join`, authToken, {
    method: 'POST',
  })
}

export async function leaveVoiceSession(sessionId: string, authToken: string | null): Promise<{ success: boolean }> {
  return requestJson<{ success: boolean }>(`${VOICE_CHANNEL_API_BASE}/sessions/${encodeURIComponent(sessionId)}/leave`, authToken, {
    method: 'POST',
  })
}

export async function fetchVoiceSession(sessionId: string, authToken: string | null): Promise<VoiceSessionDetailsResponse> {
  return requestJson<VoiceSessionDetailsResponse>(`${VOICE_CHANNEL_API_BASE}/sessions/${encodeURIComponent(sessionId)}`, authToken)
}

export async function fetchWorkspaceVoiceSessions(workspaceId: string, authToken: string | null): Promise<VoiceWorkspaceSessionsResponse> {
  return requestJson<VoiceWorkspaceSessionsResponse>(`${VOICE_CHANNEL_API_BASE}/workspaces/${encodeURIComponent(workspaceId)}/sessions`, authToken)
}

export async function fetchVoiceStats(authToken: string | null): Promise<VoiceStats> {
  return requestJson<VoiceStats>(`${VOICE_CHANNEL_API_BASE}/stats`, authToken)
}