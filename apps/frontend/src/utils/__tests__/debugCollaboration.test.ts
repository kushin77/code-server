/** @vitest-environment jsdom */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import {
  createDebugSession,
  fetchDebugSession,
  joinDebugSession,
  leaveDebugSession,
  recordDebugStep,
  relayDebugProtocolMessage,
  updateDebugBreakpoints,
  updateDebugVariables,
} from '../debugCollaboration'

const fetchMock = vi.fn()

beforeEach(() => {
  fetchMock.mockReset()
  vi.stubGlobal('fetch', fetchMock)
})

afterEach(() => {
  vi.unstubAllGlobals()
})

function buildJsonResponse(payload: unknown, ok = true, status = 200) {
  return {
    ok,
    status,
    json: async () => payload,
  } as Response
}

describe('debugCollaboration', () => {
  it('creates and loads debug sessions through the API helpers', async () => {
    fetchMock.mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))
    fetchMock.mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1', workspaceId: 'portal-main' }))

    await expect(
      createDebugSession({
        workspaceId: 'portal-main',
        actor: 'Portal main',
        debuggerName: 'Portal debugger',
        debuggerProgram: 'src/main.ts',
        debuggerCwd: '/workspace/portal',
      })
    ).resolves.toMatchObject({ sessionId: 'session-1' })

    await expect(fetchDebugSession('session-1')).resolves.toMatchObject({ workspaceId: 'portal-main' })
    expect(fetchMock).toHaveBeenCalledWith('/api/debug-sessions', expect.objectContaining({ method: 'POST' }))
  })

  it('routes join, breakpoint, variable, step, leave, and relay calls to the correct endpoints', async () => {
    fetchMock
      .mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))
      .mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))
      .mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))
      .mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))
      .mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))
      .mockResolvedValueOnce(buildJsonResponse({ sessionId: 'session-1' }))

    await joinDebugSession('session-1', 'Portal main')
    await updateDebugBreakpoints('session-1', { actor: 'Portal main', breakpoints: [] })
    await updateDebugVariables('session-1', { actor: 'Portal main', variables: [] })
    await recordDebugStep('session-1', { actor: 'Portal main', action: 'next' })
    await leaveDebugSession('session-1', 'Portal main')
    await relayDebugProtocolMessage('session-1', { actor: 'Portal main', message: { type: 'request' } })

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      '/api/debug-sessions/session-1/join',
      expect.objectContaining({ method: 'POST' })
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      '/api/debug-sessions/session-1/breakpoints',
      expect.objectContaining({ method: 'PUT' })
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      3,
      '/api/debug-sessions/session-1/variables',
      expect.objectContaining({ method: 'PUT' })
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      4,
      '/api/debug-sessions/session-1/step',
      expect.objectContaining({ method: 'POST' })
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      5,
      '/api/debug-sessions/session-1/leave',
      expect.objectContaining({ method: 'POST' })
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      6,
      '/api/debug-sessions/session-1/relay',
      expect.objectContaining({ method: 'POST' })
    )
  })
})
