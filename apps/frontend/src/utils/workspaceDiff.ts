// @file        apps/frontend/src/utils/workspaceDiff.ts
// @module      utils/workspace-diff
// @description Frontend helpers for workspace diff snapshots

export type WorkspaceDiffFileStatus = 'added' | 'modified' | 'deleted' | 'renamed' | 'copied' | 'updated' | 'unknown'

export type WorkspaceDiffFile = {
  status: WorkspaceDiffFileStatus
  path: string
  previousPath?: string
}

export type WorkspaceDiffSnapshot = {
  id: string
  userId: string
  repoPath: string
  baseRef: string
  headRef: string
  summary: string
  changedFiles: WorkspaceDiffFile[]
  generatedAt: string
}

const WORKSPACE_DIFF_API_BASE = '/api/workspace-diff'

async function requestJson<T>(input: RequestInfo | URL, init?: RequestInit, allowNotFound = false): Promise<T | null> {
  const response = await fetch(input, {
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (allowNotFound && response.status === 404) {
    return null
  }

  if (!response.ok) {
    throw new Error(`Workspace diff request failed with ${response.status}`)
  }

  return (await response.json()) as T
}

export async function fetchLatestWorkspaceDiff(userId: string, repoPath: string): Promise<WorkspaceDiffSnapshot | null> {
  const params = new URLSearchParams({ repoPath })
  return requestJson<WorkspaceDiffSnapshot>(`${WORKSPACE_DIFF_API_BASE}/latest/${encodeURIComponent(userId)}?${params.toString()}`, undefined, true)
}

export async function refreshWorkspaceDiff(userId: string, repoPath: string): Promise<WorkspaceDiffSnapshot> {
  return requestJson<WorkspaceDiffSnapshot>(`${WORKSPACE_DIFF_API_BASE}/refresh/${encodeURIComponent(userId)}`, {
    method: 'POST',
    body: JSON.stringify({ repoPath }),
  }) as Promise<WorkspaceDiffSnapshot>
}