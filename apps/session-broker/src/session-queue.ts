export type SessionQueueLane = 'fast' | 'standard'

export const DEFAULT_SESSION_QUEUE_LANE: SessionQueueLane = 'standard'

export interface SessionQueueDescriptor {
  sessionId: string
  queueLane: SessionQueueLane
  queuedAt: number
  sequence: number
}

export function normalizeSessionQueueLane(value: string | null | undefined): SessionQueueLane {
  return value?.trim().toLowerCase() === 'fast' ? 'fast' : 'standard'
}

export function compareSessionQueueDescriptors(left: SessionQueueDescriptor, right: SessionQueueDescriptor): number {
  if (left.queueLane !== right.queueLane) {
    return left.queueLane === 'fast' ? -1 : 1
  }

  if (left.queuedAt !== right.queuedAt) {
    return left.queuedAt - right.queuedAt
  }

  return left.sequence - right.sequence
}

export function estimateQueueWaitSeconds(position: number, queueLane: SessionQueueLane): number {
  const baseWait = queueLane === 'fast' ? 45 : 120
  return Math.max(30, Math.ceil(position * baseWait))
}
