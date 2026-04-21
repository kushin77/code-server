import axios, { AxiosInstance } from 'axios'

export interface SentryError {
  id: string
  title: string
  level: 'fatal' | 'error' | 'warning' | 'info' | 'debug'
  status: 'unresolved' | 'resolved' | 'ignored'
  count: number
  userCount: number
  lastSeen: string
  environment: string
  permalink?: string
}

export interface SentryProjectConfig {
  token: string
  organization: string
  project: string
  environment?: string
}

export function createSentryApiClient(token: string): AxiosInstance {
  return axios.create({
    baseURL: 'https://sentry.io/api/0',
    headers: { Authorization: `Bearer ${token}` },
    timeout: 5000,
  })
}

export async function fetchSentryErrors(
  config: SentryProjectConfig,
  apiClient: AxiosInstance = createSentryApiClient(config.token),
): Promise<SentryError[]> {
  const response = await apiClient.get(`/projects/${config.organization}/${config.project}/issues/`, {
    params: {
      query: config.environment ? `is:unresolved environment:${config.environment}` : 'is:unresolved',
      limit: 20,
    },
  })

  const issues = Array.isArray(response.data) ? response.data : response.data?.data ?? []

  return issues.map((issue: any, index: number) => ({
    id: String(issue.id ?? issue.shortId ?? issue.permalink ?? index),
    title: String(issue.title ?? 'Untitled issue'),
    level: (issue.level ?? 'error') as SentryError['level'],
    status: (issue.status ?? 'unresolved') as SentryError['status'],
    count: Number(issue.count ?? issue.timesSeen ?? 0),
    userCount: Number(issue.userCount ?? issue.user_count ?? 0),
    lastSeen: String(issue.lastSeen ?? issue.last_seen ?? ''),
    environment: String(issue.environment ?? config.environment ?? 'production'),
    permalink:
      issue.permalink ??
      `https://sentry.io/organizations/${config.organization}/issues/?query=${encodeURIComponent(
        issue.shortId ?? issue.id ?? issue.title ?? ''
      )}`,
  }))
}
