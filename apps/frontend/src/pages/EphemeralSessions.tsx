import React, { useEffect, useMemo, useState } from 'react'
import { useAuthStore } from '@/store'
import { useEphemeralSessions } from '@/hooks'
import type { EphemeralSessionStatus, SessionQueueLane } from '@/types'
import {
  formatDate,
  isApprovedDataProfile,
  normalizeDataProfile,
  normalizeUsername,
  SESSION_DATA_PROFILES,
  stateTone,
  type SessionDataProfile,
} from './ephemeralSessionsUtils'

const TTL_MIN_SECONDS = 3600
const TTL_MAX_SECONDS = 86400
const TTL_DEFAULT_SECONDS = 28800

const fieldClassName =
  'w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 shadow-sm outline-none transition focus:border-sky-500 focus:ring-4 focus:ring-sky-100'

/**
 * EphemeralSessionsPage
 * Launches, inspects, and terminates disposable code-server sessions.
 */
export function EphemeralSessionsPage() {
  const user = useAuthStore((state) => state.user)
  const {
    session,
    status,
    isLoading,
    error,
    launchSession,
    fetchSessionStatus,
    cancelSession,
    destroySession,
  } = useEphemeralSessions()

  const [ttlSeconds, setTtlSeconds] = useState(String(TTL_DEFAULT_SECONDS))
  const [dataProfile, setDataProfile] = useState<SessionDataProfile>('synthetic')
  const [priorityLane, setPriorityLane] = useState<SessionQueueLane>('standard')
  const [announcement, setAnnouncement] = useState('No session launched yet.')
  const [localError, setLocalError] = useState<string | null>(null)

  const launchUsername = useMemo(() => {
    if (!user?.email) {
      return 'guest'
    }

    return normalizeUsername(user.email, user.fullName)
  }, [user?.email, user?.fullName])

  const activeSessionId = status?.sessionId ?? session?.sessionId ?? null
  const sessionState = status?.state ?? session?.status ?? null
  const currentSession = status ?? session
  const nextActions = status?.nextActions ?? []
  const brokerUrl = session?.url ?? null
  const queueInfo = currentSession?.queue ?? null

  useEffect(() => {
    if (!activeSessionId) {
      return
    }

    void fetchSessionStatus(activeSessionId).catch(() => {
      // The hook already stores the error state; keep the UI stable here.
    })
  }, [activeSessionId])

  const handleLaunch = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setLocalError(null)

    if (!user) {
      setLocalError('Sign in first to launch a session.')
      return
    }

    const normalizedProfile = normalizeDataProfile(dataProfile)
    if (!normalizedProfile || !isApprovedDataProfile(normalizedProfile)) {
      setLocalError('Choose an approved session data profile before launching.')
      return
    }

    const parsedTtlSeconds = Number(ttlSeconds)
    if (!Number.isInteger(parsedTtlSeconds) || parsedTtlSeconds < TTL_MIN_SECONDS || parsedTtlSeconds > TTL_MAX_SECONDS) {
      setLocalError(`TTL must be between ${TTL_MIN_SECONDS} and ${TTL_MAX_SECONDS} seconds.`)
      return
    }

    try {
      const launched = await launchSession({
        userId: user.id,
        username: launchUsername,
        email: user.email,
        dataProfile: normalizedProfile,
        priorityLane,
        ttlSeconds: parsedTtlSeconds,
      })

      setAnnouncement(
        launched.status === 'queued'
          ? `Session ${launched.sessionId} queued on the ${launched.queueLane ?? priorityLane} lane. Refreshing status.`
          : `Session ${launched.sessionId} launched. Refreshing status.`
      )
      await fetchSessionStatus(launched.sessionId)
    } catch (launchError) {
      const message = launchError instanceof Error ? launchError.message : 'Failed to launch ephemeral session.'
      setLocalError(message)
    }
  }

  const handleRefresh = async () => {
    if (!activeSessionId) {
      setAnnouncement('Launch a session before requesting status.')
      return
    }

    try {
      await fetchSessionStatus(activeSessionId)
      setAnnouncement(`Session ${activeSessionId} status refreshed.`)
    } catch (refreshError) {
      const message = refreshError instanceof Error ? refreshError.message : 'Failed to refresh session status.'
      setLocalError(message)
    }
  }

  const handleCancel = async () => {
    if (!activeSessionId) {
      return
    }

    try {
      await cancelSession(activeSessionId)
      await fetchSessionStatus(activeSessionId)
      setAnnouncement(`Cancellation requested for ${activeSessionId}.`)
    } catch (cancelError) {
      const message = cancelError instanceof Error ? cancelError.message : 'Failed to cancel session.'
      setLocalError(message)
    }
  }

  const handleDestroy = async () => {
    if (!activeSessionId) {
      return
    }

    try {
      await destroySession(activeSessionId)
      setAnnouncement(`Session ${activeSessionId} destroyed.`)
    } catch (destroyError) {
      const message = destroyError instanceof Error ? destroyError.message : 'Failed to destroy session.'
      setLocalError(message)
    }
  }

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
      <header className="mb-8 flex flex-col gap-4 rounded-3xl border border-slate-200 bg-gradient-to-br from-slate-950 via-slate-900 to-sky-900 px-6 py-8 text-white shadow-xl shadow-slate-200/60 sm:px-8">
        <div className="max-w-3xl space-y-3">
          <p className="text-xs font-semibold uppercase tracking-[0.32em] text-sky-200">Ephemeral sessions</p>
          <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">Launch, inspect, and terminate disposable code-server sessions.</h2>
          <p className="text-sm leading-6 text-slate-200 sm:text-base">
            Use the current account to launch a short-lived session, review the broker URL and lifecycle state, and tear it down when you are done.
          </p>
        </div>

        <div className="grid gap-3 rounded-2xl border border-white/10 bg-white/5 p-4 text-sm text-slate-100 sm:grid-cols-3">
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-300">Account</p>
            <p className="mt-1 font-medium">{user?.email ?? 'No authenticated user'}</p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-300">Username</p>
            <p className="mt-1 font-medium">{user ? launchUsername : 'guest'}</p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-300">Session state</p>
            <p className="mt-1 font-medium">{sessionState ?? 'idle'}</p>
          </div>
        </div>
      </header>

      <div className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
        <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-200/60">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.28em] text-sky-700">Launch</p>
              <h3 className="mt-2 text-2xl font-semibold text-slate-900">Create a session</h3>
            </div>
            <span className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs font-medium text-slate-600">
              TTL {TTL_MIN_SECONDS / 3600}-{TTL_MAX_SECONDS / 3600}h
            </span>
          </div>

          <form className="mt-6 space-y-4" onSubmit={handleLaunch}>
            <label className="block">
              <span className="mb-2 block text-sm font-medium text-slate-700">Data profile</span>
              <select
                aria-label="Data profile"
                className={fieldClassName}
                name="dataProfile"
                value={dataProfile}
                onChange={(event) => {
                  setDataProfile(event.target.value as SessionDataProfile)
                  setLocalError(null)
                }}
              >
                {SESSION_DATA_PROFILES.map((profile) => (
                  <option key={profile} value={profile}>
                    {profile}
                  </option>
                ))}
              </select>
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-medium text-slate-700">TTL seconds</span>
              <input
                aria-label="TTL seconds"
                className={fieldClassName}
                inputMode="numeric"
                min={TTL_MIN_SECONDS}
                max={TTL_MAX_SECONDS}
                name="ttlSeconds"
                type="number"
                value={ttlSeconds}
                onChange={(event) => {
                  setTtlSeconds(event.target.value)
                  setLocalError(null)
                }}
              />
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-medium text-slate-700">Queue lane</span>
              <select
                aria-label="Queue lane"
                className={fieldClassName}
                name="priorityLane"
                value={priorityLane}
                onChange={(event) => {
                  setPriorityLane(event.target.value as SessionQueueLane)
                  setLocalError(null)
                }}
              >
                <option value="standard">standard</option>
                <option value="fast">fast</option>
              </select>
            </label>

            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
              <p className="font-medium text-slate-900">Launch identity</p>
              <p className="mt-1">{user ? `${user.email} → ${launchUsername}` : 'Sign in to launch a session.'}</p>
              <p className="mt-1">
                Approved data profile: <span className="font-semibold text-slate-900">{dataProfile}</span>
              </p>
              <p className="mt-1">
                Queue lane: <span className="font-semibold text-slate-900">{priorityLane}</span>
              </p>
            </div>

            {(localError || error) && (
              <div role="alert" className="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
                {localError || error}
              </div>
            )}

            <button
              className="inline-flex w-full items-center justify-center rounded-2xl bg-sky-600 px-4 py-3 text-sm font-semibold text-white transition hover:bg-sky-700 disabled:cursor-not-allowed disabled:bg-slate-300"
              disabled={isLoading || !user}
              type="submit"
            >
              {isLoading ? 'Launching…' : 'Launch session'}
            </button>
          </form>
        </section>

        <section className="space-y-6">
          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-200/60">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.28em] text-sky-700">Status</p>
                <h3 className="mt-2 text-2xl font-semibold text-slate-900">Current session</h3>
              </div>

              <button
                className="inline-flex items-center justify-center rounded-xl border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!activeSessionId || isLoading}
                onClick={handleRefresh}
                type="button"
              >
                Refresh status
              </button>
            </div>

            <div className="mt-6 space-y-4">
              {currentSession ? (
                <>
                  <div className="flex flex-wrap items-center gap-3">
                    <span className={`rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] ${stateTone(sessionState)}`}>
                      {sessionState ?? 'unknown'}
                    </span>
                    <span className="text-sm text-slate-500" aria-live="polite">
                      {announcement}
                    </span>
                  </div>

                  <dl className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Session ID</dt>
                      <dd className="mt-2 break-all font-medium text-slate-900">{currentSession.sessionId}</dd>
                    </div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Container</dt>
                      <dd className="mt-2 font-medium text-slate-900">{currentSession.containerName}</dd>
                    </div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Broker URL</dt>
                      <dd className="mt-2 break-all font-medium text-slate-900">
                        {brokerUrl ? (
                          <a className="text-sky-700 underline decoration-sky-300 underline-offset-4 hover:text-sky-900" href={brokerUrl} rel="noreferrer" target="_blank">
                            {brokerUrl}
                          </a>
                        ) : (
                          'Waiting for broker URL'
                        )}
                      </dd>
                    </div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Port</dt>
                      <dd className="mt-2 font-medium text-slate-900">{currentSession.containerPort}</dd>
                    </div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Data profile</dt>
                      <dd className="mt-2 font-medium text-slate-900">{currentSession.dataProfile}</dd>
                      <p className="mt-1 text-xs text-slate-500">
                        {currentSession.dataProfileValidated ? 'Approved synthetic or masked dataset' : 'Profile not validated'}
                      </p>
                    </div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Expires</dt>
                      <dd className="mt-2 font-medium text-slate-900">{formatDate(currentSession.expiresAt)}</dd>
                    </div>
                    {queueInfo && (
                      <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                        <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Queue</dt>
                        <dd className="mt-2 font-medium text-slate-900">{queueInfo.lane} lane</dd>
                        <p className="mt-1 text-xs text-slate-500">
                          Position {queueInfo.position ?? 'pending'} · ETA {queueInfo.estimatedWaitSeconds ?? 'unknown'}s
                        </p>
                        <p className="mt-1 text-xs text-slate-500">
                          Enqueued {formatDate(queueInfo.enqueuedAt)}
                        </p>
                      </div>
                    )}
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <dt className="text-xs uppercase tracking-[0.2em] text-slate-500">Last activity</dt>
                      <dd className="mt-2 font-medium text-slate-900">{formatDate(currentSession.lastActivity)}</dd>
                    </div>
                  </dl>

                  {queueInfo && (
                    <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
                      <p className="font-semibold">Queued session</p>
                      <p className="mt-1">
                        {queueInfo.reason ?? 'Waiting for capacity.'} Position {queueInfo.position ?? 'pending'} on the {queueInfo.lane} lane.
                      </p>
                    </div>
                  )}

                  {'active' in currentSession && (
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
                      <p>
                        Active: <span className="font-semibold text-slate-900">{(currentSession as EphemeralSessionStatus).active ? 'yes' : 'no'}</span>
                        {' · '}
                        Terminal: <span className="font-semibold text-slate-900">{(currentSession as EphemeralSessionStatus).terminal ? 'yes' : 'no'}</span>
                      </p>
                      <p className="mt-1">Next actions: {nextActions.length > 0 ? nextActions.join(', ') : 'none'}</p>
                    </div>
                  )}
                </>
              ) : (
                <div className="rounded-2xl border border-dashed border-slate-300 bg-slate-50 px-5 py-10 text-center text-sm text-slate-600">
                  Launch a session to view the broker URL, lifecycle state, and teardown controls here.
                </div>
              )}
            </div>
          </div>

          <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-200/60">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.28em] text-sky-700">Controls</p>
                <h3 className="mt-2 text-2xl font-semibold text-slate-900">Terminate or reset</h3>
              </div>
              <p className="text-sm text-slate-500">All controls are keyboard accessible and announce state changes.</p>
            </div>

            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <button
                className="inline-flex items-center justify-center rounded-2xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm font-semibold text-amber-900 transition hover:bg-amber-100 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!activeSessionId || isLoading || sessionState === 'destroyed'}
                onClick={handleCancel}
                type="button"
              >
                Cancel session
              </button>
              <button
                className="inline-flex items-center justify-center rounded-2xl border border-rose-300 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-900 transition hover:bg-rose-100 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!activeSessionId || isLoading || sessionState === 'destroyed'}
                onClick={handleDestroy}
                type="button"
              >
                Destroy now
              </button>
            </div>

            <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
              <p className="font-medium text-slate-900">Lifecycle summary</p>
              <p className="mt-1">
                {activeSessionId ? `Session ${activeSessionId} is ${sessionState ?? 'unknown'}.` : 'No active ephemeral session.'}
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
  )
}
