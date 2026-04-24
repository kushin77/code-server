/** @vitest-environment jsdom */

import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { CollaborativeDebuggingPanel } from '../CollaborativeDebuggingPanel'

const createDebugSession = vi.fn()
const fetchDebugSession = vi.fn()
const fetchRelayedDebugMessages = vi.fn()
const joinDebugSession = vi.fn()
const leaveDebugSession = vi.fn()
const recordDebugStep = vi.fn()
const relayDebugProtocolMessage = vi.fn()
const updateDebugBreakpoints = vi.fn()
const updateDebugVariables = vi.fn()

vi.mock('../../utils/debugCollaboration', () => ({
  createDebugSession: (...args: unknown[]) => createDebugSession(...args),
  fetchDebugSession: (...args: unknown[]) => fetchDebugSession(...args),
  fetchRelayedDebugMessages: (...args: unknown[]) => fetchRelayedDebugMessages(...args),
  joinDebugSession: (...args: unknown[]) => joinDebugSession(...args),
  leaveDebugSession: (...args: unknown[]) => leaveDebugSession(...args),
  recordDebugStep: (...args: unknown[]) => recordDebugStep(...args),
  relayDebugProtocolMessage: (...args: unknown[]) => relayDebugProtocolMessage(...args),
  updateDebugBreakpoints: (...args: unknown[]) => updateDebugBreakpoints(...args),
  updateDebugVariables: (...args: unknown[]) => updateDebugVariables(...args),
}))

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

beforeEach(() => {
  createDebugSession.mockResolvedValue({
    sessionId: 'session-1',
    workspaceId: 'portal-main',
    debuggerName: 'Portal debugger',
    debuggerProgram: 'src/main.ts',
    debuggerCwd: '/workspace/portal',
    owner: 'Portal main',
    relaySequence: 0,
    participants: [
      {
        actor: 'Portal main',
        role: 'owner',
        joinedAt: '2026-04-22T00:00:00.000Z',
        lastSeenAt: '2026-04-22T00:00:00.000Z',
      },
    ],
    breakpoints: [],
    variables: [],
    stepEvents: [],
    relayMessages: [],
    createdAt: '2026-04-22T00:00:00.000Z',
    updatedAt: '2026-04-22T00:00:00.000Z',
  })

  fetchDebugSession.mockResolvedValue({
    sessionId: 'session-1',
    workspaceId: 'portal-main',
    debuggerName: 'Portal debugger',
    debuggerProgram: 'src/main.ts',
    debuggerCwd: '/workspace/portal',
    owner: 'Portal main',
    relaySequence: 1,
    participants: [
      {
        actor: 'Portal main',
        role: 'owner',
        joinedAt: '2026-04-22T00:00:00.000Z',
        lastSeenAt: '2026-04-22T00:00:00.000Z',
      },
    ],
    breakpoints: [
      {
        id: 'bp-1',
        filePath: 'src/app.ts',
        line: 42,
        verified: true,
      },
    ],
    variables: [],
    stepEvents: [],
    relayMessages: [],
    createdAt: '2026-04-22T00:00:00.000Z',
    updatedAt: '2026-04-22T00:00:05.000Z',
  })

  fetchRelayedDebugMessages.mockResolvedValue({
    sessionId: 'session-1',
    relayTarget: 'https://relay.example.test/dap',
    latestSequence: 0,
    messages: [],
  })

  joinDebugSession.mockResolvedValue(fetchDebugSession.mock.results[0]?.value)
  leaveDebugSession.mockResolvedValue(fetchDebugSession.mock.results[0]?.value)
  recordDebugStep.mockResolvedValue(fetchDebugSession.mock.results[0]?.value)
  relayDebugProtocolMessage.mockResolvedValue(fetchDebugSession.mock.results[0]?.value)
  updateDebugBreakpoints.mockResolvedValue(fetchDebugSession.mock.results[0]?.value)
  updateDebugVariables.mockResolvedValue(fetchDebugSession.mock.results[0]?.value)
})

describe('CollaborativeDebuggingPanel', () => {
  it('refreshes remote session state and polls relay deltas after creating a session', async () => {
    render(
      <CollaborativeDebuggingPanel
        workspaceId="portal-main"
        actorName="Portal main"
        debuggerName="Portal debugger"
        debuggerProgram="src/main.ts"
        debuggerCwd="/workspace/portal"
      />
    )

    fireEvent.click(screen.getByRole('button', { name: 'Create shared session' }))

    await waitFor(() => expect(createDebugSession).toHaveBeenCalled())
    await waitFor(() => expect(fetchDebugSession).toHaveBeenCalledWith('session-1'))
    await waitFor(() => expect(fetchRelayedDebugMessages).toHaveBeenCalledWith('session-1', 'Portal main', 0))

    expect(screen.getByText('src/app.ts:42')).toBeTruthy()
    expect(screen.getByText('session-1')).toBeTruthy()
  })
})