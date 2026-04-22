import { useCallback, useEffect, useMemo, useState } from 'react'

import {
  createDebugSession,
  fetchDebugSession,
  fetchRelayedDebugMessages,
  joinDebugSession,
  leaveDebugSession,
  recordDebugStep,
  relayDebugProtocolMessage,
  updateDebugBreakpoints,
  updateDebugVariables,
  type DebugBreakpoint,
  type DebugSessionRecord,
  type DebugStepAction,
  type DebugVariableSnapshot,
} from '../utils/debugCollaboration'
import { analyzeDebugSession, type DebugSessionInsight } from '../utils/debugSessionInsights'

export type CollaborativeDebuggingPanelProps = {
  workspaceId: string
  actorName: string
  debuggerName: string
  debuggerProgram: string
  debuggerCwd: string
}

const STEP_ACTIONS: DebugStepAction[] = ['continue', 'next', 'stepIn', 'stepOut', 'pause']

function isDebugSessionRecord(value: DebugSessionRecord | null): value is DebugSessionRecord {
  return Boolean(value)
}

function getSessionStorage() {
  if (typeof window === 'undefined') {
    return undefined
  }

  return typeof window.localStorage?.getItem === 'function' && typeof window.localStorage?.setItem === 'function'
    ? window.localStorage
    : undefined
}

export function CollaborativeDebuggingPanel({
  workspaceId,
  actorName,
  debuggerName,
  debuggerProgram,
  debuggerCwd,
}: CollaborativeDebuggingPanelProps) {
  const storageKey = useMemo(() => `debug-session:${workspaceId}`, [workspaceId])
  const [sessionId, setSessionId] = useState('')
  const [relayTarget, setRelayTarget] = useState('')
  const [session, setSession] = useState<DebugSessionRecord | null>(null)
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [breakpointPath, setBreakpointPath] = useState(debuggerProgram)
  const [breakpointLine, setBreakpointLine] = useState('1')
  const [breakpointCondition, setBreakpointCondition] = useState('')
  const [variableScope, setVariableScope] = useState('locals')
  const [variableName, setVariableName] = useState('state')
  const [variableValue, setVariableValue] = useState('ready')
  const [stepAction, setStepAction] = useState<DebugStepAction>('next')
  const [stepNote, setStepNote] = useState('')
  const insights = useMemo<DebugSessionInsight[]>(() => analyzeDebugSession(session), [session])

  const refreshSession = useCallback(
    async (nextSessionId?: string) => {
      if (!nextSessionId) {
        return
      }

      try {
        setError(null)
        const nextSession = await fetchDebugSession(nextSessionId)
        setSession(nextSession)
        setStatus(`Loaded session ${nextSession.sessionId}`)
        getSessionStorage()?.setItem(storageKey, nextSession.sessionId)
      } catch (fetchError) {
        setError(fetchError instanceof Error ? fetchError.message : 'Unable to load debug session')
      }
    },
    [storageKey]
  )

  useEffect(() => {
    const storedSessionId = getSessionStorage()?.getItem(storageKey)
    if (!storedSessionId) {
      return
    }

    setSessionId(storedSessionId)
    void refreshSession(storedSessionId)
  }, [refreshSession, storageKey])

  useEffect(() => {
    if (!session?.sessionId) {
      return
    }

    let cancelled = false

    const syncRemoteSession = async () => {
      try {
        const nextSession = await fetchDebugSession(session.sessionId)

        if (cancelled) {
          return
        }

        setSession(nextSession)
      } catch (syncError) {
        if (!cancelled) {
          setError(syncError instanceof Error ? syncError.message : 'Unable to sync debug session')
        }
      }
    }

    const relaySequence = session.relaySequence ?? 0
    const syncRelayMessages = async () => {
      try {
        const relaySync = await fetchRelayedDebugMessages(session.sessionId, actorName, relaySequence)

        if (cancelled || relaySync.messages.length === 0) {
          return
        }

        setSession((current) => {
          if (!current || current.sessionId !== relaySync.sessionId) {
            return current
          }

          const knownMessageIds = new Set(current.relayMessages.map((relayMessage) => relayMessage.id))
          const relayMessages = [
            ...current.relayMessages,
            ...relaySync.messages.filter((relayMessage) => !knownMessageIds.has(relayMessage.id)),
          ].sort((left, right) => left.sequence - right.sequence)

          return {
            ...current,
            relayMessages,
            relaySequence: relaySync.latestSequence,
          }
        })
      } catch {
        // Relay polling is best-effort; session refresh remains authoritative.
      }
    }

    void syncRemoteSession()
    void syncRelayMessages()

    const intervalId = window.setInterval(() => {
      void syncRemoteSession()
      void syncRelayMessages()
    }, 3000)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [actorName, session?.sessionId, session?.relaySequence])

  async function persistSession(nextSession: DebugSessionRecord) {
    setSession(nextSession)
    setSessionId(nextSession.sessionId)
    setStatus(`Session ${nextSession.sessionId} is ready for collaboration`)
    setError(null)

    getSessionStorage()?.setItem(storageKey, nextSession.sessionId)
  }

  async function handleCreateSession() {
    try {
      const nextSession = await createDebugSession({
        workspaceId,
        actor: actorName,
        debuggerName,
        debuggerProgram,
        debuggerCwd,
        relayTarget: relayTarget.trim() || undefined,
      })

      await persistSession(nextSession)
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'Unable to create debug session')
    }
  }

  async function handleJoinSession() {
    if (!sessionId.trim()) {
      setError('Enter a debug session id to join')
      return
    }

    try {
      const nextSession = await joinDebugSession(sessionId.trim(), actorName)
      await persistSession(nextSession)
    } catch (joinError) {
      setError(joinError instanceof Error ? joinError.message : 'Unable to join debug session')
    }
  }

  async function handleLeaveSession() {
    if (!isDebugSessionRecord(session)) {
      return
    }

    try {
      const nextSession = await leaveDebugSession(session.sessionId, actorName)
      await persistSession(nextSession)
      setStatus(`Left session ${nextSession.sessionId}`)
    } catch (leaveError) {
      setError(leaveError instanceof Error ? leaveError.message : 'Unable to leave debug session')
    }
  }

  async function handleAddBreakpoint() {
    if (!isDebugSessionRecord(session)) {
      setError('Create or join a session before adding breakpoints')
      return
    }

    const nextBreakpoint: DebugBreakpoint = {
      filePath: breakpointPath.trim() || debuggerProgram,
      line: Number(breakpointLine) || 1,
      condition: breakpointCondition.trim() || undefined,
      verified: true,
    }

    try {
      const nextSession = await updateDebugBreakpoints(session.sessionId, {
        actor: actorName,
        breakpoints: [...session.breakpoints, nextBreakpoint],
      })
      await persistSession(nextSession)
      setStatus(`Shared breakpoint added to ${nextBreakpoint.filePath}:${nextBreakpoint.line}`)
    } catch (breakpointError) {
      setError(breakpointError instanceof Error ? breakpointError.message : 'Unable to update breakpoints')
    }
  }

  async function handleCaptureVariable() {
    if (!isDebugSessionRecord(session)) {
      setError('Create or join a session before inspecting variables')
      return
    }

    const nextVariable: DebugVariableSnapshot = {
      scope: variableScope.trim() || 'locals',
      name: variableName.trim() || 'value',
      value: variableValue,
    }

    try {
      const nextSession = await updateDebugVariables(session.sessionId, {
        actor: actorName,
        variables: [...session.variables, nextVariable],
      })
      await persistSession(nextSession)
      setStatus(`Captured variable ${nextVariable.scope}.${nextVariable.name}`)
    } catch (variableError) {
      setError(variableError instanceof Error ? variableError.message : 'Unable to update variables')
    }
  }

  async function handleStep() {
    if (!isDebugSessionRecord(session)) {
      setError('Create or join a session before stepping through code')
      return
    }

    try {
      const steppedSession = await recordDebugStep(session.sessionId, {
        actor: actorName,
        action: stepAction,
        note: stepNote.trim() || undefined,
      })
      const relayedSession = await relayDebugProtocolMessage(session.sessionId, {
        actor: actorName,
        relayTarget: relayTarget.trim() || session.relayTarget,
        message: {
          type: 'request',
          command: stepAction,
          arguments: {
            note: stepNote.trim() || undefined,
          },
        },
      })

      await persistSession({ ...relayedSession, stepEvents: steppedSession.stepEvents })
      setStatus(`Shared ${stepAction} action with the debug relay`)
    } catch (stepError) {
      setError(stepError instanceof Error ? stepError.message : 'Unable to record the step action')
    }
  }

  const sessionLabel = session?.sessionId || sessionId || 'No shared session yet'

  return (
    <div className="rounded-2xl border border-violet-200 bg-violet-50 p-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-violet-700">Collaborative debugging</p>
          <h3 className="mt-1 text-lg font-semibold text-slate-900">Share breakpoints, variables, and step actions</h3>
          <p className="mt-1 max-w-2xl text-sm text-slate-600">
            Create a shared session for {debuggerName}. The panel records collaborator presence, captured variables, step events, and optional DAP relay traffic.
          </p>
        </div>

        <div className="rounded-2xl bg-white px-4 py-3 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Current session</p>
          <p className="mt-1 text-sm font-semibold text-slate-900">{sessionLabel}</p>
          <p className="text-xs text-slate-500">Actor: {actorName}</p>
        </div>
      </div>

      <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
        <div className="space-y-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="grid gap-3 md:grid-cols-2">
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Session id</span>
              <input
                value={sessionId}
                onChange={(event) => setSessionId(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
                placeholder="Create or join a session"
              />
            </label>
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Relay target</span>
              <input
                value={relayTarget}
                onChange={(event) => setRelayTarget(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
                placeholder="https://debug-relay.example.test"
              />
            </label>
          </div>

          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => void handleCreateSession()} className="rounded-full bg-violet-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-violet-700">
              Create shared session
            </button>
            <button type="button" onClick={() => void handleJoinSession()} className="rounded-full border border-violet-300 px-4 py-2 text-sm font-medium text-violet-700 transition hover:border-violet-500 hover:bg-violet-50">
              Join session
            </button>
            <button type="button" onClick={() => void refreshSession(session?.sessionId || sessionId)} className="rounded-full border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:bg-slate-50">
              Refresh
            </button>
            <button type="button" onClick={() => void handleLeaveSession()} className="rounded-full border border-rose-200 px-4 py-2 text-sm font-medium text-rose-700 transition hover:border-rose-400 hover:bg-rose-50">
              Leave session
            </button>
          </div>

          <div className="grid gap-3 md:grid-cols-2">
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Breakpoint file</span>
              <input
                value={breakpointPath}
                onChange={(event) => setBreakpointPath(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
                placeholder="src/server.ts"
              />
            </label>
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Breakpoint line</span>
              <input
                value={breakpointLine}
                onChange={(event) => setBreakpointLine(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
                inputMode="numeric"
                placeholder="1"
              />
            </label>
          </div>

          <label className="block text-sm">
            <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Breakpoint condition</span>
            <input
              value={breakpointCondition}
              onChange={(event) => setBreakpointCondition(event.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
              placeholder="request.userId === actorId"
            />
          </label>

          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => void handleAddBreakpoint()} className="rounded-full bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-700">
              Share breakpoint
            </button>
            <button type="button" onClick={() => void handleCaptureVariable()} className="rounded-full border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-violet-400 hover:text-violet-700">
              Capture variable snapshot
            </button>
          </div>

          <div className="grid gap-3 md:grid-cols-3">
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Variable scope</span>
              <input
                value={variableScope}
                onChange={(event) => setVariableScope(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
              />
            </label>
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Variable name</span>
              <input
                value={variableName}
                onChange={(event) => setVariableName(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
              />
            </label>
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Variable value</span>
              <input
                value={variableValue}
                onChange={(event) => setVariableValue(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
              />
            </label>
          </div>

          <div className="grid gap-3 md:grid-cols-[0.7fr_1.3fr]">
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Step action</span>
              <select
                value={stepAction}
                onChange={(event) => setStepAction(event.target.value as DebugStepAction)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
              >
                {STEP_ACTIONS.map((action) => (
                  <option key={action} value={action}>
                    {action}
                  </option>
                ))}
              </select>
            </label>
            <label className="block text-sm">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Step note</span>
              <input
                value={stepNote}
                onChange={(event) => setStepNote(event.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
                placeholder="Explain what the shared step should inspect"
              />
            </label>
          </div>

          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => void handleStep()} className="rounded-full bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-700">
              Relay step action
            </button>
          </div>

          {status ? <p className="text-sm font-medium text-emerald-700">{status}</p> : null}
          {error ? <p className="text-sm font-medium text-rose-700">{error}</p> : null}
        </div>

        <div className="space-y-4 rounded-2xl border border-slate-200 bg-slate-50 p-4">
          <div className="rounded-2xl border border-slate-200 bg-white p-3">
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Participants</p>
            <div className="mt-2 space-y-2 text-sm text-slate-700">
              {session?.participants?.length ? (
                session.participants.map((participant) => (
                  <div key={participant.actor} className="rounded-xl bg-slate-50 px-3 py-2">
                    <p className="font-medium text-slate-900">{participant.actor}</p>
                    <p className="text-xs text-slate-500">{participant.role} · joined {participant.joinedAt}</p>
                  </div>
                ))
              ) : (
                <p className="text-slate-500">No collaborators yet.</p>
              )}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-3">
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Breakpoints</p>
            <div className="mt-2 space-y-2 text-sm text-slate-700">
              {session?.breakpoints?.length ? (
                session.breakpoints.map((breakpoint) => (
                  <div key={breakpoint.id || `${breakpoint.filePath}:${breakpoint.line}`} className="rounded-xl bg-slate-50 px-3 py-2">
                    <p className="font-medium text-slate-900">{breakpoint.filePath}:{breakpoint.line}</p>
                    <p className="text-xs text-slate-500">{breakpoint.condition || 'No condition'} · {breakpoint.verified ? 'verified' : 'pending'}</p>
                  </div>
                ))
              ) : (
                <p className="text-slate-500">No shared breakpoints captured yet.</p>
              )}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-3">
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Variables</p>
            <div className="mt-2 space-y-2 text-sm text-slate-700">
              {session?.variables?.length ? (
                session.variables.map((variable) => (
                  <div key={`${variable.scope}.${variable.name}`} className="rounded-xl bg-slate-50 px-3 py-2">
                    <p className="font-medium text-slate-900">{variable.scope}.{variable.name}</p>
                    <p className="text-xs text-slate-500">{variable.value}</p>
                  </div>
                ))
              ) : (
                <p className="text-slate-500">No variable snapshots captured yet.</p>
              )}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-3">
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Step log</p>
            <div className="mt-2 space-y-2 text-sm text-slate-700">
              {session?.stepEvents?.length ? (
                session.stepEvents.map((stepEvent) => (
                  <div key={stepEvent.id} className="rounded-xl bg-slate-50 px-3 py-2">
                    <p className="font-medium text-slate-900">{stepEvent.action}</p>
                    <p className="text-xs text-slate-500">{stepEvent.actor} · {stepEvent.timestamp}</p>
                    {stepEvent.note ? <p className="mt-1 text-xs text-slate-700">{stepEvent.note}</p> : null}
                  </div>
                ))
              ) : (
                <p className="text-slate-500">No step activity recorded yet.</p>
              )}
            </div>
          </div>
          <div className="rounded-2xl border border-violet-200 bg-violet-50 p-3">
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-violet-700">AI debug insights</p>
            <div className="mt-2 space-y-3 text-sm text-slate-700">
              {insights.length ? (
                insights.map((insight) => (
                  <div key={insight.title} className="rounded-xl border border-violet-200 bg-white px-3 py-2 shadow-sm">
                    <div className="flex items-center justify-between gap-3">
                      <p className="font-semibold text-slate-900">{insight.title}</p>
                      <p className="text-xs font-medium uppercase tracking-[0.16em] text-violet-700">{Math.round(insight.confidence)}%</p>
                    </div>
                    <p className="mt-1 text-xs text-slate-500">Root cause: {insight.rootCause}</p>
                    <p className="mt-1 text-xs text-slate-700">Fix: {insight.fixApproach}</p>
                    <p className="mt-1 text-xs text-slate-500">Docs: {insight.relevantDocs.join(', ')}</p>
                    {insight.evidence.length ? <p className="mt-1 text-xs text-slate-500">Evidence: {insight.evidence.join(' · ')}</p> : null}
                  </div>
                ))
              ) : (
                <p className="text-slate-500">Capture or join a session to generate debug insights.</p>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
