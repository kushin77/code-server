/** @vitest-environment jsdom */

import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'

import { VoiceChannelPanel } from '../VoiceChannelPanel'

const createVoiceSession = vi.fn()
const fetchVoiceStats = vi.fn()
const fetchWorkspaceVoiceSessions = vi.fn()
const joinVoiceSession = vi.fn()
const leaveVoiceSession = vi.fn()
const fetchTeamRichPresence = vi.fn()
const upsertRichPresence = vi.fn()

vi.mock('../../utils/voiceChannel', () => ({
  createVoiceSession: (...args: unknown[]) => createVoiceSession(...args),
  fetchVoiceStats: (...args: unknown[]) => fetchVoiceStats(...args),
  fetchWorkspaceVoiceSessions: (...args: unknown[]) => fetchWorkspaceVoiceSessions(...args),
  joinVoiceSession: (...args: unknown[]) => joinVoiceSession(...args),
  leaveVoiceSession: (...args: unknown[]) => leaveVoiceSession(...args),
}))

vi.mock('../../utils/richPresence', () => ({
  fetchTeamRichPresence: (...args: unknown[]) => fetchTeamRichPresence(...args),
  upsertRichPresence: (...args: unknown[]) => upsertRichPresence(...args),
}))

afterEach(() => {
  cleanup()
  createVoiceSession.mockReset()
  fetchVoiceStats.mockReset()
  fetchWorkspaceVoiceSessions.mockReset()
  joinVoiceSession.mockReset()
  leaveVoiceSession.mockReset()
  fetchTeamRichPresence.mockReset()
  upsertRichPresence.mockReset()
})

describe('VoiceChannelPanel', () => {
  it('loads voice stats and allows session creation and join', async () => {
    fetchWorkspaceVoiceSessions.mockResolvedValue({
      sessions: [
        {
          sessionId: 'session-1',
          workspaceId: 'portal-main',
          userId: 'alice',
          liveKitToken: 'token-1',
          liveKitRoomName: 'workspace-portal-main',
          startedAt: 1,
          participantCount: 2,
          status: 'active',
        },
      ],
      count: 1,
    })
    fetchVoiceStats.mockResolvedValue({
      activeSessionsCount: 1,
      totalParticipants: 2,
      averageLatencyMs: 42,
      audioQualityP50: 90,
      audioQualityP95: 95,
      noiseReductionEnabled: true,
      timestamp: 1,
    })
    fetchTeamRichPresence.mockResolvedValue({
      teamId: 'team-main',
      count: 1,
      presence: [
        {
          teamId: 'team-main',
          userId: 'alice',
          displayName: 'Alice Chen',
          status: 'online',
          updatedAt: '2026-04-22T00:00:00.000Z',
          expiresAt: '2026-04-22T00:05:00.000Z',
        },
      ],
    })
    createVoiceSession.mockResolvedValue({
      session: {
        sessionId: 'session-2',
        workspaceId: 'portal-main',
        userId: 'alice',
        liveKitToken: 'token-2',
        liveKitRoomName: 'workspace-portal-main',
        startedAt: 2,
        participantCount: 1,
        status: 'active',
      },
      token: 'token-2',
      liveKitUrl: 'wss://livekit.example',
    })
    joinVoiceSession.mockResolvedValue({
      session: {
        sessionId: 'session-1',
        workspaceId: 'portal-main',
        userId: 'alice',
        liveKitToken: 'token-1',
        liveKitRoomName: 'workspace-portal-main',
        startedAt: 1,
        participantCount: 2,
        status: 'active',
      },
      token: 'token-1',
      liveKitUrl: 'wss://livekit.example',
    })
    leaveVoiceSession.mockResolvedValue({ success: true })

    render(
      <VoiceChannelPanel
        workspaceId="portal-main"
        workspaceLabel="Portal main"
        teamId="team-main"
        currentUserId="alice"
        currentDisplayName="Alice Chen"
        authToken="token"
      />
    )

    expect(await screen.findByText('Live voice for Portal main')).toBeTruthy()
    expect(screen.getByText('1')).toBeTruthy()
    expect(screen.getByText('2')).toBeTruthy()
    expect(screen.getByText('workspace-portal-main')).toBeTruthy()

    fireEvent.click(screen.getByRole('button', { name: 'Start voice session' }))

    await waitFor(() => {
      expect(createVoiceSession).toHaveBeenCalledWith('portal-main', 'token')
    })
    await waitFor(() => {
      expect(upsertRichPresence).toHaveBeenCalledWith(
        'team-main',
        'alice',
        expect.objectContaining({
          status: 'dnd',
          customStatus: '📞 In a voice session',
        })
      )
    })

    fireEvent.change(screen.getByLabelText('Join by session ID'), { target: { value: 'session-1' } })
    fireEvent.click(screen.getByRole('button', { name: 'Join voice session' }))

    await waitFor(() => {
      expect(joinVoiceSession).toHaveBeenCalledWith('session-1', 'token')
    })

    fireEvent.click(screen.getByRole('button', { name: 'Leave active session' }))

    await waitFor(() => {
      expect(leaveVoiceSession).toHaveBeenCalledWith('session-1', 'token')
    })
    await waitFor(() => {
      expect(upsertRichPresence).toHaveBeenCalledWith(
        'team-main',
        'alice',
        expect.objectContaining({
          status: 'online',
          customStatus: null,
        })
      )
    })
  })
})