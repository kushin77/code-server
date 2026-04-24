import axios from 'axios'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { DebugSessionCollaborationService } from '../index'

vi.mock('axios', () => ({
  default: {
    post: vi.fn(),
  },
}))

vi.mock('../../../lib/tracing.js', () => ({
  extractTraceHeaders: vi.fn(() => ({ traceparent: '00-abcdef0123456789abcdef0123456789-abcdef0123456789-01' })),
  getTracer: vi.fn(() => ({})),
  withSpan: vi.fn(async (_tracer, _name, _attributes, fn) => {
    const span = {
      setAttribute: vi.fn(),
      setStatus: vi.fn(),
      recordException: vi.fn(),
      end: vi.fn(),
    }
    return fn(span as any)
  }),
}))

describe('DebugSessionCollaborationService', () => {
  let service: DebugSessionCollaborationService

  beforeEach(() => {
    service = new DebugSessionCollaborationService()
    vi.mocked(axios.post).mockReset()
    vi.mocked(axios.post).mockResolvedValue({ status: 200, data: {} })
  })

  it('creates a collaborative debug session and tracks session state', () => {
    const session = service.createSession({
      workspaceId: 'portal-main',
      actor: 'Portal main',
      debuggerName: 'Portal debugger',
      debuggerProgram: 'src/main.ts',
      debuggerCwd: '/workspace/portal',
    })

    expect(session.workspaceId).toBe('portal-main')
    expect(session.owner).toBe('Portal main')
    expect(session.participants).toHaveLength(1)

    const joined = service.joinSession(session.sessionId, 'Design review', 'collaborator')
    expect(joined.participants.map((participant) => participant.actor)).toContain('Design review')

    const updatedBreakpoints = service.updateBreakpoints(session.sessionId, {
      actor: 'Portal main',
      breakpoints: [{ filePath: 'src/main.ts', line: 18, condition: 'ready' }],
    })

    expect(updatedBreakpoints.breakpoints).toHaveLength(1)
    expect(updatedBreakpoints.breakpoints[0].filePath).toBe('src/main.ts')
    expect(updatedBreakpoints.breakpoints[0].verified).toBe(true)

    const updatedVariables = service.updateVariables(session.sessionId, {
      actor: 'Portal main',
      variables: [{ scope: 'locals', name: 'status', value: 'running' }],
    })

    expect(updatedVariables.variables).toHaveLength(1)
    expect(updatedVariables.variables[0].name).toBe('status')

    const stepped = service.recordStep(session.sessionId, {
      actor: 'Portal main',
      action: 'stepIn',
      note: 'Inspecting the request handler',
    })

    expect(stepped.stepEvents).toHaveLength(1)
    expect(stepped.stepEvents[0].action).toBe('stepIn')
  })

  it('relays DAP messages through the configured target', async () => {
    const session = service.createSession({
      workspaceId: 'portal-main',
      actor: 'Portal main',
      debuggerName: 'Portal debugger',
      debuggerProgram: 'src/main.ts',
      debuggerCwd: '/workspace/portal',
      relayTarget: 'https://relay.example.test/dap',
    })

    const relayed = await service.relayDapMessage(session.sessionId, {
      actor: 'Portal main',
      message: { type: 'request', command: 'next', arguments: { threadId: 1 } },
    })

    expect(axios.post).toHaveBeenCalledWith('https://relay.example.test/dap', {
      sessionId: session.sessionId,
      actor: 'Portal main',
      message: { type: 'request', command: 'next', arguments: { threadId: 1 } },
      timestamp: expect.any(String),
    }, {
      headers: {
        traceparent: '00-abcdef0123456789abcdef0123456789-abcdef0123456789-01',
      },
    })
    expect(relayed.relayMessages).toHaveLength(1)
    expect(relayed.relayMessages[0].forwarded).toBe(true)
    expect(relayed.relayMessages[0].sequence).toBe(1)
  })

  it('returns relay message deltas using a sequence cursor', async () => {
    const session = service.createSession({
      workspaceId: 'portal-main',
      actor: 'Portal main',
      debuggerName: 'Portal debugger',
      debuggerProgram: 'src/main.ts',
      debuggerCwd: '/workspace/portal',
    })

    await service.relayDapMessage(session.sessionId, {
      actor: 'Portal main',
      message: { type: 'request', command: 'stepIn' },
    })
    await service.relayDapMessage(session.sessionId, {
      actor: 'Portal main',
      message: { type: 'request', command: 'next' },
    })

    const allMessages = service.listRelayMessages(session.sessionId, 'Portal main', 0)
    expect(allMessages.latestSequence).toBe(2)
    expect(allMessages.messages).toHaveLength(2)
    expect(allMessages.messages[0].sequence).toBe(1)
    expect(allMessages.messages[1].sequence).toBe(2)

    const deltaMessages = service.listRelayMessages(session.sessionId, 'Portal main', 1)
    expect(deltaMessages.latestSequence).toBe(2)
    expect(deltaMessages.messages).toHaveLength(1)
    expect(deltaMessages.messages[0].message).toMatchObject({ command: 'next' })
  })

  it('rejects updates from actors who have not joined the session', () => {
    const session = service.createSession({
      workspaceId: 'portal-main',
      actor: 'Portal main',
      debuggerName: 'Portal debugger',
      debuggerProgram: 'src/main.ts',
      debuggerCwd: '/workspace/portal',
    })

    expect(() =>
      service.updateBreakpoints(session.sessionId, {
        actor: 'Unjoined reviewer',
        breakpoints: [{ filePath: 'src/main.ts', line: 10 }],
      })
    ).toThrow(/is not part of debug session/)
  })
})
