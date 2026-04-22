// @file        apps/frontend/src/utils/richPresence.ts
// @module      utils/rich-presence
// @description Frontend helpers for team rich presence snapshots

export type RichPresenceStatus = 'online' | 'away' | 'dnd' | 'offline'

export type RichPresenceRecord = {
  teamId: string
  userId: string
  displayName: string
  status: RichPresenceStatus
  currentFile?: string | null
  currentFunction?: string | null
  currentTask?: string | null
  customStatus?: string | null
  updatedAt: string
  expiresAt: string
}

export type RichPresenceTeamSnapshot = {
  teamId: string
  count: number
  presence: RichPresenceRecord[]
}

export type RichPresenceUpsertInput = {
  displayName?: string
  status?: RichPresenceStatus
  currentFile?: string | null
  currentFunction?: string | null
  currentTask?: string | null
  customStatus?: string | null
}

const RICH_PRESENCE_API_BASE = '/api/rich-presence'

async function requestJson<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, {
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (!response.ok) {
    throw new Error(`Rich presence request failed with ${response.status}`)
  }

  return (await response.json()) as T
}

export async function fetchTeamRichPresence(teamId: string): Promise<RichPresenceTeamSnapshot> {
  return requestJson<RichPresenceTeamSnapshot>(`${RICH_PRESENCE_API_BASE}/teams/${encodeURIComponent(teamId)}/presence`)
}

export async function upsertRichPresence(teamId: string, userId: string, input: RichPresenceUpsertInput): Promise<RichPresenceRecord> {
  return requestJson<RichPresenceRecord>(`${RICH_PRESENCE_API_BASE}/teams/${encodeURIComponent(teamId)}/users/${encodeURIComponent(userId)}`, {
    method: 'POST',
    body: JSON.stringify(input),
  })
}