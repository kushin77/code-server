// @file        apps/frontend/src/utils/__tests__/collaborationMetrics.test.ts
// @module      utils/__tests__/collaboration-metrics
// @description Unit tests for collaboration metrics helpers

import { describe, expect, it, vi } from 'vitest'

import {
  fetchOpenPullRequestCount,
  getDemoTeamOnlineCount,
  getDemoTeamStatusCounts,
  getGitHubHandleFromEmail,
} from '../collaborationMetrics'

describe('collaborationMetrics', () => {
  it('derives a github handle from an email address', () => {
    expect(getGitHubHandleFromEmail('Alex.Kushnir@example.com')).toBe('alex.kushnir')
    expect(getGitHubHandleFromEmail('')).toBeNull()
  })

  it('exposes the demo team online count', () => {
    expect(getDemoTeamOnlineCount()).toBe(3)
    expect(getDemoTeamStatusCounts()).toEqual({ online: 3, away: 1, offline: 2 })
  })

  it('fetches a PR count from the GitHub search API', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: vi.fn().mockResolvedValue({ total_count: 7 }),
    })

    vi.stubGlobal('fetch', fetchMock)

    await expect(fetchOpenPullRequestCount('kushin77/code-server', 'alex')).resolves.toBe(7)
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining('repo%3Akushin77%2Fcode-server'),
      expect.objectContaining({
        headers: expect.objectContaining({
          Accept: 'application/vnd.github+json',
        }),
      })
    )

    vi.unstubAllGlobals()
  })
})