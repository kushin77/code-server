// @file        apps/frontend/src/utils/symbolDiscussions.ts
// @module      utils/symbol-discussions
// @description Frontend helpers for inline symbol discussion lookups

export type SymbolDiscussionCommentReaction = {
  emoji: string
  user: string
  timestamp: string
}

export type SymbolDiscussionComment = {
  id: string
  threadId: string
  author: string
  content: string
  createdAt: string
  updatedAt: string
  isEdited: boolean
  parentCommentId?: string
  reactions: SymbolDiscussionCommentReaction[]
}

export type SymbolDiscussionThread = {
  id: string
  title: string
  createdBy: string
  createdAt: string
  updatedAt: string
  isResolved: boolean
  resolvedAt?: string
  resolvedBy?: string
  comments: SymbolDiscussionComment[]
}

export type SymbolDiscussion = {
  id: string
  fqn: string
  filePath: string
  symbolName: string
  symbolType: 'function' | 'class' | 'method' | 'variable' | 'interface' | 'type'
  lineNumber: number
  createdAt: string
  updatedAt: string
  thread: SymbolDiscussionThread
}

export type SymbolDiscussionLocationResult = {
  filePath: string
  lineNumber?: number
  count: number
  discussions: SymbolDiscussion[]
}

const SYMBOL_DISCUSSIONS_API_BASE = '/api/symbol-discussions'

async function requestJson<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, {
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (!response.ok) {
    throw new Error(`Symbol discussion request failed with ${response.status}`)
  }

  return (await response.json()) as T
}

export async function fetchSymbolDiscussionsByLocation(
  filePath: string,
  lineNumber?: number
): Promise<SymbolDiscussionLocationResult> {
  const params = new URLSearchParams({ filePath })

  if (lineNumber !== undefined && Number.isFinite(lineNumber)) {
    params.set('lineNumber', String(Math.max(1, Math.trunc(lineNumber))))
  }

  return requestJson<SymbolDiscussionLocationResult>(`${SYMBOL_DISCUSSIONS_API_BASE}/location?${params.toString()}`)
}
