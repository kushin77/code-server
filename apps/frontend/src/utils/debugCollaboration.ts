export type DebugSessionParticipantRole = 'owner' | 'collaborator' | 'observer'

export type DebugStepAction = 'continue' | 'next' | 'stepIn' | 'stepOut' | 'pause'

export type DebugBreakpoint = {
  id?: string
  filePath: string
  line: number
  column?: number
  condition?: string
  hitCondition?: string
  logMessage?: string
  verified?: boolean
}

export type DebugVariableSnapshot = {
  scope: string
  name: string
  value: string
  type?: string
  variablesReference?: number
}

export type DebugSessionParticipant = {
  actor: string
  role: DebugSessionParticipantRole
  joinedAt: string
  lastSeenAt: string
}

export type DebugStepEvent = {
  id: string
  actor: string
  action: DebugStepAction
  note?: string
  timestamp: string
}

export type DebugRelayMessage = {
  id: string
  actor: string
  message: Record<string, unknown>
  relayTarget?: string
  forwarded: boolean
  timestamp: string
}

export type DebugSessionRecord = {
  sessionId: string
  workspaceId: string
  debuggerName: string
  debuggerProgram: string
  debuggerCwd: string
  owner: string
  relayTarget?: string
  participants: DebugSessionParticipant[]
  breakpoints: DebugBreakpoint[]
  variables: DebugVariableSnapshot[]
  stepEvents: DebugStepEvent[]
  relayMessages: DebugRelayMessage[]
  createdAt: string
  updatedAt: string
}

export type CreateDebugSessionInput = {
  workspaceId: string
  actor: string
  debuggerName: string
  debuggerProgram: string
  debuggerCwd: string
  relayTarget?: string
}

export type UpdateDebugBreakpointsInput = {
  actor: string
  breakpoints: DebugBreakpoint[]
}

export type UpdateDebugVariablesInput = {
  actor: string
  variables: DebugVariableSnapshot[]
}

export type RecordDebugStepInput = {
  actor: string
  action: DebugStepAction
  note?: string
}

export type RelayDebugMessageInput = {
  actor: string
  message: Record<string, unknown>
  relayTarget?: string
}

const DEBUG_SESSION_API_BASE = '/api/debug-sessions'

async function requestJson<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, {
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (!response.ok) {
    throw new Error(`Debug collaboration request failed with ${response.status}`)
  }

  return (await response.json()) as T
}

export async function fetchDebugSession(sessionId: string): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}`)
}

export async function createDebugSession(input: CreateDebugSessionInput): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(DEBUG_SESSION_API_BASE, {
    method: 'POST',
    body: JSON.stringify(input),
  })
}

export async function joinDebugSession(sessionId: string, actor: string, role: DebugSessionParticipantRole = 'collaborator'): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}/join`, {
    method: 'POST',
    body: JSON.stringify({ actor, role }),
  })
}

export async function leaveDebugSession(sessionId: string, actor: string): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}/leave`, {
    method: 'POST',
    body: JSON.stringify({ actor }),
  })
}

export async function updateDebugBreakpoints(sessionId: string, input: UpdateDebugBreakpointsInput): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}/breakpoints`, {
    method: 'PUT',
    body: JSON.stringify(input),
  })
}

export async function updateDebugVariables(sessionId: string, input: UpdateDebugVariablesInput): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}/variables`, {
    method: 'PUT',
    body: JSON.stringify(input),
  })
}

export async function recordDebugStep(sessionId: string, input: RecordDebugStepInput): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}/step`, {
    method: 'POST',
    body: JSON.stringify(input),
  })
}

export async function relayDebugProtocolMessage(sessionId: string, input: RelayDebugMessageInput): Promise<DebugSessionRecord> {
  return requestJson<DebugSessionRecord>(`${DEBUG_SESSION_API_BASE}/${sessionId}/relay`, {
    method: 'POST',
    body: JSON.stringify(input),
  })
}
