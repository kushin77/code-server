// @file        apps/frontend/src/utils/collaborationMetrics.ts
// @module      utils/collaboration-metrics
// @description Collaboration status bar metrics and demo presence helpers

import { fetchPagerDutyIncidents } from '@/extensions/pagerduty-incidents.js'

const DEMO_TEAM_USERS = [
  { id: 'alice', displayName: 'Alice Chen', status: 'online' as const },
  { id: 'bob', displayName: 'Bob Kumar', status: 'online' as const },
  { id: 'carol', displayName: 'Carol Wang', status: 'online' as const },
  { id: 'dave', displayName: 'Dave Lee', status: 'away' as const },
  { id: 'eve', displayName: 'Eve Park', status: 'offline' as const },
  { id: 'frank', displayName: 'Frank Wu', status: 'offline' as const },
]

export const PAGERDUTY_INCIDENTS_ROUTE = '/pagerduty-incidents'
export const TEAM_HUB_ROUTE = '/team-hub'

export function getGitHubHandleFromEmail(email?: string | null): string | null {
  if (!email) {
    return null
  }

  const [localPart] = email.split('@')
  const handle = localPart.trim().toLowerCase()
  return handle.length > 0 ? handle : null
}

export function getDemoTeamOnlineCount(): number {
  return DEMO_TEAM_USERS.filter((user) => user.status === 'online').length
}

export function getDemoTeamStatusCounts(): { online: number; away: number; offline: number } {
  return {
    online: DEMO_TEAM_USERS.filter((user) => user.status === 'online').length,
    away: DEMO_TEAM_USERS.filter((user) => user.status === 'away').length,
    offline: DEMO_TEAM_USERS.filter((user) => user.status === 'offline').length,
  }
}

export function getDemoTeamNamesByStatus(status: 'online' | 'away' | 'offline'): string[] {
  return DEMO_TEAM_USERS.filter((user) => user.status === status).map((user) => user.displayName)
}

export async function fetchOpenPullRequestCount(repoSlug: string, authorLogin: string | null): Promise<number | null> {
  if (!repoSlug || !authorLogin) {
    return null
  }

  try {
    const query = `is:open is:pr repo:${repoSlug} author:${authorLogin}`
    const response = await fetch(`https://api.github.com/search/issues?q=${encodeURIComponent(query)}`, {
      headers: {
        Accept: 'application/vnd.github+json',
      },
    })

    if (!response.ok) {
      return null
    }

    const data = (await response.json()) as { total_count?: unknown }
    return typeof data.total_count === 'number' ? data.total_count : null
  } catch {
    return null
  }
}

export async function fetchActivePagerDutyIncidentCount(token: string | null): Promise<number | null> {
  if (!token) {
    return null
  }

  try {
    const { stats } = await fetchPagerDutyIncidents({ token })
    return stats.total
  } catch {
    return null
  }
}