import type { DebugSessionRecord } from './debugCollaboration'

export type DebugSessionInsight = {
  title: string
  rootCause: string
  fixApproach: string
  relevantDocs: string[]
  confidence: number
  evidence: string[]
}

function normalizeText(value: string | null | undefined): string {
  return typeof value === 'string' ? value.trim() : ''
}

function unique(values: string[]): string[] {
  return Array.from(new Set(values.filter(Boolean)))
}

function isSuspiciousValue(value: string): boolean {
  return /^(undefined|null|nan)?$/i.test(value) || /error|fail|exception|timeout/i.test(value)
}

export function analyzeDebugSession(session: DebugSessionRecord | null): DebugSessionInsight[] {
  if (!session) {
    return []
  }

  const insights: DebugSessionInsight[] = []

  const suspiciousVariables = session.variables
    .map((variable) => ({
      scope: normalizeText(variable.scope),
      name: normalizeText(variable.name),
      value: normalizeText(variable.value),
    }))
    .filter((variable) => isSuspiciousValue(variable.value))

  if (suspiciousVariables.length > 0) {
    insights.push({
      title: 'Likely null or uninitialized debug state',
      rootCause: `Captured variables look unstable: ${suspiciousVariables.map((variable) => `${variable.scope}.${variable.name}`).join(', ')}`,
      fixApproach:
        'Step back to the branch that produces the value, add a guard for missing payloads, and capture a fresh snapshot before the breakpoint fires again.',
      relevantDocs: ['docs/README.md', 'docs/ops/README.md'],
      confidence: Math.min(96, 74 + suspiciousVariables.length * 6),
      evidence: suspiciousVariables.map((variable) => `${variable.scope}.${variable.name}=${variable.value}`),
    })
  }

  const breakpointCounts = new Map<string, number>()
  for (const breakpoint of session.breakpoints) {
    const filePath = normalizeText(breakpoint.filePath)
    if (!filePath) {
      continue
    }

    breakpointCounts.set(filePath, (breakpointCounts.get(filePath) ?? 0) + 1)
  }

  const hotFiles = Array.from(breakpointCounts.entries()).filter(([, count]) => count >= 2)
  if (hotFiles.length > 0) {
    insights.push({
      title: 'The failing path is concentrated in one file',
      rootCause: `Multiple breakpoints are stacked in ${hotFiles.map(([filePath]) => filePath).join(', ')}`,
      fixApproach:
        'Treat this as a flow problem instead of a single line bug: instrument the entry and exit points, then compare the captured values across each breakpoint.',
      relevantDocs: ['docs/README.md', 'docs/status/README.md'],
      confidence: 68 + Math.min(18, hotFiles.length * 4),
      evidence: hotFiles.map(([filePath, count]) => `${filePath} (${count} breakpoints)`),
    })
  }

  const unresolvedRelays = session.relayMessages.filter((relayMessage) => relayMessage.relayTarget && !relayMessage.forwarded)
  if (session.relayTarget && unresolvedRelays.length > 0) {
    insights.push({
      title: 'Debug relay may be dropping messages',
      rootCause: `Relay target ${session.relayTarget} has not acknowledged every forwarded DAP message.`,
      fixApproach:
        'Check the relay endpoint health, confirm the DAP transport contract, and retry the step after a successful relay handshake.',
      relevantDocs: ['docs/ops/README.md', 'docs/ops/DEPLOYMENT-CHECKLIST.md'],
      confidence: 79,
      evidence: unresolvedRelays.map((relayMessage) => relayMessage.relayTarget || session.relayTarget || 'unknown relay target'),
    })
  }

  const pauseEvents = session.stepEvents.filter((stepEvent) => stepEvent.action === 'pause' || stepEvent.action === 'stepIn')
  if (pauseEvents.length > 0 && session.variables.length === 0) {
    insights.push({
      title: 'Capture state before the next step',
      rootCause: 'The session has stepping activity but no variable snapshots, so the failure path is still opaque.',
      fixApproach:
        'Pause again at the failing branch, capture locals and watched expressions, and compare the state before and after the step.',
      relevantDocs: ['docs/README.md', 'docs/status/README.md'],
      confidence: 72,
      evidence: pauseEvents.slice(0, 3).map((stepEvent) => `${stepEvent.action} by ${stepEvent.actor}`),
    })
  }

  if (insights.length === 0) {
    insights.push({
      title: 'Capture one more variable snapshot',
      rootCause: 'There is not enough debug state yet to predict the failure confidently.',
      fixApproach:
        'Add one breakpoint around the failing branch, record the watched variables, and step once more before asking for an AI diagnosis.',
      relevantDocs: ['docs/README.md', 'docs/status/README.md'],
      confidence: 55,
      evidence: unique([
        `breakpoints=${session.breakpoints.length}`,
        `variables=${session.variables.length}`,
        `steps=${session.stepEvents.length}`,
      ]),
    })
  }

  return insights.sort((left, right) => right.confidence - left.confidence).slice(0, 3)
}