import { useEffect, useMemo, useRef, useState } from 'react'

import {
  createVoiceSession,
  fetchVoiceStats,
  fetchWorkspaceVoiceSessions,
  joinVoiceSession,
  leaveVoiceSession,
  type VoiceSession,
  type VoiceStats,
} from '../utils/voiceChannel'
import {
  fetchTeamRichPresence,
  upsertRichPresence,
  type RichPresenceStatus,
} from '../utils/richPresence'

export type VoiceChannelPanelProps = {
  workspaceId: string
  workspaceLabel: string
  teamId?: string | null
  currentUserId: string | null
  currentDisplayName: string | null
  authToken: string | null
}

function formatLatency(value: number): string {
  return `${Math.round(value)}ms`
}

export function VoiceChannelPanel({
  workspaceId,
  workspaceLabel,
  teamId,
  currentUserId,
  currentDisplayName,
  authToken,
}: VoiceChannelPanelProps) {
  const [sessions, setSessions] = useState<VoiceSession[]>([])
  const [stats, setStats] = useState<VoiceStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [joinSessionId, setJoinSessionId] = useState('')
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null)
  const [operation, setOperation] = useState<string | null>(null)
  const previousPresenceStatusRef = useRef<RichPresenceStatus | null>(null)

  const activeSession = useMemo(
    () => sessions.find((session) => session.sessionId === activeSessionId) ?? null,
    [activeSessionId, sessions]
  )

  const meetingModeActive = Boolean(activeSessionId && teamId && currentUserId)

  const updateMeetingPresence = async (nextStatus: RichPresenceStatus): Promise<void> => {
    if (!teamId || !currentUserId) {
      return
    }

    try {
      if (nextStatus === 'dnd') {
        const snapshot = await fetchTeamRichPresence(teamId)
        const currentPresence = snapshot.presence.find((entry) => entry.userId === currentUserId)
        previousPresenceStatusRef.current = currentPresence?.status ?? 'online'
      }

      await upsertRichPresence(teamId, currentUserId, {
        displayName: currentDisplayName ?? undefined,
        status: nextStatus,
        currentTask: nextStatus === 'dnd' ? 'In a voice session' : null,
        customStatus: nextStatus === 'dnd' ? '📞 In a voice session' : null,
      })
    } catch {
      // Keep voice flow resilient if presence sync fails.
    }
  }

  const restoreMeetingPresence = async (): Promise<void> => {
    if (!teamId || !currentUserId) {
      return
    }

    const restoreStatus = previousPresenceStatusRef.current ?? 'online'
    previousPresenceStatusRef.current = null

    try {
      await upsertRichPresence(teamId, currentUserId, {
        displayName: currentDisplayName ?? undefined,
        status: restoreStatus,
        currentTask: null,
        customStatus: null,
      })
    } catch {
      // Keep voice flow resilient if presence sync fails.
    }
  }

  const loadVoiceData = async () => {
    setLoading(true)
    setError(null)

    try {
      const [workspaceSessions, nextStats] = await Promise.all([
        fetchWorkspaceVoiceSessions(workspaceId, authToken),
        fetchVoiceStats(authToken),
      ])

      setSessions(workspaceSessions.sessions)
      setStats(nextStats)
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Unable to load voice channel data')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    let cancelled = false

    const refresh = async () => {
      try {
        const [workspaceSessions, nextStats] = await Promise.all([
          fetchWorkspaceVoiceSessions(workspaceId, authToken),
          fetchVoiceStats(authToken),
        ])

        if (!cancelled) {
          setSessions(workspaceSessions.sessions)
          setStats(nextStats)
        }
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError instanceof Error ? loadError.message : 'Unable to load voice channel data')
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    void refresh()

    const refreshHandle = window.setInterval(() => {
      void loadVoiceData()
    }, 60 * 1000)

    return () => {
      cancelled = true
      window.clearInterval(refreshHandle)
    }
  }, [authToken, workspaceId])

  const handleCreateSession = async () => {
    if (!currentUserId) {
      setError('Sign in to start a voice session')
      return
    }

    setOperation('Creating session...')
    setError(null)

    try {
      const nextSession = await createVoiceSession(workspaceId, authToken)
      setActiveSessionId(nextSession.session.sessionId)
      await updateMeetingPresence('dnd')
      await loadVoiceData()
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'Unable to create voice session')
    } finally {
      setOperation(null)
    }
  }

  const handleJoinSession = async (sessionId?: string) => {
    const nextSessionId = sessionId ?? joinSessionId.trim()
    if (!nextSessionId) {
      setError('Enter a session ID to join')
      return
    }

    setOperation('Joining session...')
    setError(null)

    try {
      const nextSession = await joinVoiceSession(nextSessionId, authToken)
      setActiveSessionId(nextSession.session.sessionId)
      setJoinSessionId('')
      await updateMeetingPresence('dnd')
      await loadVoiceData()
    } catch (joinError) {
      setError(joinError instanceof Error ? joinError.message : 'Unable to join voice session')
    } finally {
      setOperation(null)
    }
  }

  const handleLeaveSession = async () => {
    if (!activeSessionId) {
      return
    }

    setOperation('Leaving session...')
    setError(null)

    try {
      await leaveVoiceSession(activeSessionId, authToken)
      await restoreMeetingPresence()
      setActiveSessionId(null)
      await loadVoiceData()
    } catch (leaveError) {
      setError(leaveError instanceof Error ? leaveError.message : 'Unable to leave voice session')
    } finally {
      setOperation(null)
    }
  }

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-100">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-violet-700">Voice channel</p>
          <div className="mt-1 flex flex-wrap items-center gap-2">
            <h3 className="text-xl font-bold text-slate-900">Live voice for {workspaceLabel}</h3>
            {meetingModeActive ? (
              <span className="inline-flex items-center rounded-full border border-violet-200 bg-violet-50 px-2 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-violet-800">
                📞 Meeting mode active
              </span>
            ) : null}
          </div>
          <p className="mt-2 max-w-2xl text-sm text-slate-600">
            Start or join a workspace voice session from the IDE shell. The backend issues LiveKit session tokens and tracks participant health.
          </p>
        </div>

        <div className="grid gap-3 sm:grid-cols-2 xl:min-w-[320px]">
          <div className="rounded-2xl bg-violet-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-violet-700">Active sessions</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{stats?.activeSessionsCount ?? '—'}</p>
          </div>
          <div className="rounded-2xl bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Participants</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{stats?.totalParticipants ?? '—'}</p>
          </div>
        </div>
      </div>

      <div className="mt-5 grid gap-6 xl:grid-cols-[minmax(0,1fr)_340px]">
        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Latency</p>
              <p className="mt-1 text-lg font-semibold text-slate-900">{stats ? formatLatency(stats.averageLatencyMs) : '—'}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Noise cancellation</p>
              <p className="mt-1 text-lg font-semibold text-slate-900">{stats?.noiseReductionEnabled ? 'Enabled' : 'Disabled'}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Quality p95</p>
              <p className="mt-1 text-lg font-semibold text-slate-900">{stats ? `${stats.audioQualityP95}/100` : '—'}</p>
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Workspace sessions</p>
                <p className="mt-1 text-sm text-slate-600">
                  {loading ? 'Loading the latest voice sessions...' : `${sessions.length} sessions tracked in this workspace`}
                </p>
              </div>
              <button
                type="button"
                onClick={() => void loadVoiceData()}
                className="rounded-full border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-violet-400 hover:text-violet-700"
              >
                Refresh
              </button>
            </div>

            <div className="mt-4 space-y-3">
              {sessions.length > 0 ? (
                sessions.map((session) => (
                  <div key={session.sessionId} className="rounded-2xl border border-slate-200 bg-white px-4 py-3">
                    <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
                      <div>
                        <p className="text-sm font-semibold text-slate-900">{session.liveKitRoomName}</p>
                        <p className="text-xs text-slate-500">Session {session.sessionId}</p>
                        <p className="mt-1 text-sm text-slate-600">
                          {session.participantCount} participant{session.participantCount === 1 ? '' : 's'} · {session.status}
                        </p>
                      </div>
                      <button
                        type="button"
                        onClick={() => void handleJoinSession(session.sessionId)}
                        className="rounded-full border border-violet-300 bg-violet-50 px-3 py-2 text-sm font-medium text-violet-800 transition hover:border-violet-400 hover:bg-violet-100"
                      >
                        Join session
                      </button>
                    </div>
                  </div>
                ))
              ) : (
                <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-4 py-8 text-center text-sm text-slate-600">
                  No voice sessions are active in this workspace yet.
                </div>
              )}
            </div>
          </div>

          {error ? <p className="text-sm font-medium text-rose-700">{error}</p> : null}
        </div>

        <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Control panel</p>
          <p className="mt-1 text-sm text-slate-600">
            {currentUserId ? `Signed in as ${currentDisplayName ?? currentUserId}` : 'Sign in to create or join a session.'}
          </p>

          <div className="mt-4 space-y-3">
            <button
              type="button"
              onClick={() => void handleCreateSession()}
              disabled={!currentUserId || Boolean(operation)}
              className="w-full rounded-full bg-violet-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-violet-700 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Start voice session
            </button>

            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Join by session ID</span>
              <input
                value={joinSessionId}
                onChange={(event) => setJoinSessionId(event.target.value)}
                placeholder="session-123"
                className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900"
              />
            </label>

            <button
              type="button"
              onClick={() => void handleJoinSession()}
              disabled={!joinSessionId.trim() || Boolean(operation)}
              className="w-full rounded-full border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-violet-400 hover:text-violet-700 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Join voice session
            </button>

            <button
              type="button"
              onClick={() => void handleLeaveSession()}
              disabled={!activeSessionId || Boolean(operation)}
              className="w-full rounded-full border border-rose-300 bg-white px-4 py-2 text-sm font-semibold text-rose-700 transition hover:border-rose-400 hover:bg-rose-50 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Leave active session
            </button>
          </div>

          <div className="mt-4 rounded-2xl border border-slate-200 bg-white px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Active session</p>
            {activeSession ? (
              <div className="mt-2 space-y-1 text-sm text-slate-700">
                <p className="font-medium text-slate-900">{activeSession.liveKitRoomName}</p>
                <p>{activeSession.participantCount} participant{activeSession.participantCount === 1 ? '' : 's'}</p>
                <p className="text-xs text-slate-500">Token issued by backend; connect with LiveKit client tooling.</p>
              </div>
            ) : (
              <p className="mt-2 text-sm text-slate-600">No active session selected.</p>
            )}
          </div>

          {operation ? <p className="mt-3 text-sm font-medium text-slate-600">{operation}</p> : null}
        </div>
      </div>
    </section>
  )
}
