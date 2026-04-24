/** @vitest-environment jsdom */

import { describe, expect, it } from 'vitest'

import { analyzeDebugSession } from '../debugSessionInsights'
import type { DebugSessionRecord } from '../debugCollaboration'

function buildSession(overrides: Partial<DebugSessionRecord> = {}): DebugSessionRecord {
  return {
    sessionId: 'session-1',
    workspaceId: 'portal-main',
    debuggerName: 'Portal debugger',
    debuggerProgram: 'src/main.ts',
    debuggerCwd: '/workspace/portal',
    owner: 'Portal main',
    relaySequence: 0,
    participants: [],
    breakpoints: [],
    variables: [],
    stepEvents: [],
    relayMessages: [],
    createdAt: '2026-04-22T00:00:00.000Z',
    updatedAt: '2026-04-22T00:00:00.000Z',
    ...overrides,
  }
}

describe('analyzeDebugSession', () => {
  it('flags unstable variable snapshots and returns docs references', () => {
    const insights = analyzeDebugSession(
      buildSession({
        variables: [{ scope: 'locals', name: 'userId', value: 'undefined' }],
        breakpoints: [
          { id: 'bp-1', filePath: 'src/main.ts', line: 18, verified: true },
          { id: 'bp-2', filePath: 'src/main.ts', line: 44, verified: true },
        ],
      })
    )

    expect(insights[0].title).toContain('null or uninitialized')
    expect(insights[0].relevantDocs).toContain('docs/README.md')
    expect(insights[0].evidence).toContain('locals.userId=undefined')
  })

  it('warns when relay messages are not forwarded', () => {
    const insights = analyzeDebugSession(
      buildSession({
        relayTarget: 'https://relay.example.test/dap',
        relayMessages: [
          {
            id: 'relay-1',
            actor: 'Portal main',
            message: { type: 'request', command: 'next' },
            relayTarget: 'https://relay.example.test/dap',
            forwarded: false,
            timestamp: '2026-04-22T00:00:00.000Z',
          },
        ],
      })
    )

    expect(insights.some((insight) => insight.title.includes('Debug relay'))).toBe(true)
  })
})