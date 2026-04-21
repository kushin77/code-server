import { useEffect, useRef, useState } from 'react'

export type ExtensionProfilerSampleKind = 'activation' | 'mount' | 'load' | 'refresh'

export type ExtensionProfilerStatus = 'success' | 'warning' | 'error'

export type ExtensionProfilerSample = {
  id: string
  label: string
  category: string
  kind: ExtensionProfilerSampleKind
  status: ExtensionProfilerStatus
  durationMs: number
  measuredAt: number
  note?: string
}

export type ExtensionProfilerSnapshot = {
  samples: ExtensionProfilerSample[]
  updatedAt: number
}

const STORAGE_KEY = 'ide-profiler:extension-samples'
const MAX_SAMPLES = 50
const fallbackStorage = new Map<string, string>()

function getStorage(): Storage | undefined {
  if (typeof window === 'undefined') {
    return undefined
  }

  return window.localStorage
}

function readSnapshot(): ExtensionProfilerSnapshot {
  const storage = getStorage()
  if (!storage || typeof storage.getItem !== 'function') {
    const rawValue = fallbackStorage.get(STORAGE_KEY)
    if (!rawValue) {
      return { samples: [], updatedAt: Date.now() }
    }

    try {
      const parsedValue = JSON.parse(rawValue) as Partial<ExtensionProfilerSnapshot>
      if (!Array.isArray(parsedValue.samples)) {
        return { samples: [], updatedAt: Date.now() }
      }

      return {
        samples: parsedValue.samples.filter(isProfilerSample),
        updatedAt: typeof parsedValue.updatedAt === 'number' ? parsedValue.updatedAt : Date.now(),
      }
    } catch {
      return { samples: [], updatedAt: Date.now() }
    }
  }

  try {
    const rawValue = storage.getItem(STORAGE_KEY)
    if (!rawValue) {
      return { samples: [], updatedAt: Date.now() }
    }

    const parsedValue = JSON.parse(rawValue) as Partial<ExtensionProfilerSnapshot>
    if (!Array.isArray(parsedValue.samples)) {
      return { samples: [], updatedAt: Date.now() }
    }

    return {
      samples: parsedValue.samples.filter(isProfilerSample),
      updatedAt: typeof parsedValue.updatedAt === 'number' ? parsedValue.updatedAt : Date.now(),
    }
  } catch {
    return { samples: [], updatedAt: Date.now() }
  }
}

function writeSnapshot(snapshot: ExtensionProfilerSnapshot): void {
  const storage = getStorage()
  if (!storage || typeof storage.setItem !== 'function') {
    fallbackStorage.set(STORAGE_KEY, JSON.stringify(snapshot))
    return
  }

  storage.setItem(STORAGE_KEY, JSON.stringify(snapshot))
  window.dispatchEvent(new CustomEvent('ide-profiler:extension-samples'))
}

function isProfilerSample(value: unknown): value is ExtensionProfilerSample {
  if (!value || typeof value !== 'object') {
    return false
  }

  const candidate = value as Partial<ExtensionProfilerSample>
  return (
    typeof candidate.id === 'string' &&
    typeof candidate.label === 'string' &&
    typeof candidate.category === 'string' &&
    (candidate.kind === 'activation' || candidate.kind === 'mount' || candidate.kind === 'load' || candidate.kind === 'refresh') &&
    (candidate.status === 'success' || candidate.status === 'warning' || candidate.status === 'error') &&
    typeof candidate.durationMs === 'number' &&
    typeof candidate.measuredAt === 'number'
  )
}

function toStatus(durationMs: number, note?: string): ExtensionProfilerStatus {
  if (note) {
    return 'warning'
  }

  if (durationMs >= 500) {
    return 'warning'
  }

  return 'success'
}

function upsertSample(sample: ExtensionProfilerSample): void {
  const snapshot = readSnapshot()
  const nextSamples = [sample, ...snapshot.samples.filter((existing) => existing.id !== sample.id)]
    .sort((left, right) => right.measuredAt - left.measuredAt)
    .slice(0, MAX_SAMPLES)

  writeSnapshot({ samples: nextSamples, updatedAt: Date.now() })
}

export function getExtensionProfilerSnapshot(): ExtensionProfilerSnapshot {
  return readSnapshot()
}

export function resetExtensionProfilerSamples(): void {
  const storage = getStorage()
  if (storage && typeof storage.removeItem === 'function') {
    storage.removeItem(STORAGE_KEY)
  } else {
    fallbackStorage.delete(STORAGE_KEY)
  }

  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('ide-profiler:extension-samples'))
  }
}

export function recordExtensionProfilerSample(input: {
  id: string
  label: string
  category: string
  kind: ExtensionProfilerSampleKind
  durationMs: number
  note?: string
}): ExtensionProfilerSample {
  const sample: ExtensionProfilerSample = {
    ...input,
    status: toStatus(input.durationMs, input.note),
    measuredAt: Date.now(),
  }

  upsertSample(sample)
  return sample
}

export function measureExtensionProfiler<T>(
  input: Omit<Parameters<typeof recordExtensionProfilerSample>[0], 'durationMs'>,
  operation: () => T,
): T {
  const startedAt = performance.now()

  try {
    const result = operation()
    const durationMs = performance.now() - startedAt
    recordExtensionProfilerSample({ ...input, durationMs })
    return result
  } catch (error) {
    const durationMs = performance.now() - startedAt
    recordExtensionProfilerSample({
      ...input,
      durationMs,
      note: error instanceof Error ? error.message : 'Operation failed',
    })
    throw error
  }
}

export async function measureAsyncExtensionProfiler<T>(
  input: Omit<Parameters<typeof recordExtensionProfilerSample>[0], 'durationMs'>,
  operation: () => Promise<T>,
): Promise<T> {
  const startedAt = performance.now()

  try {
    const result = await operation()
    const durationMs = performance.now() - startedAt
    recordExtensionProfilerSample({ ...input, durationMs })
    return result
  } catch (error) {
    const durationMs = performance.now() - startedAt
    recordExtensionProfilerSample({
      ...input,
      durationMs,
      note: error instanceof Error ? error.message : 'Operation failed',
    })
    throw error
  }
}

export function useExtensionMountProfiler(input: {
  id: string
  label: string
  category: string
  note?: string
}): void {
  const mountedAt = useRef<number>(performance.now())
  const recorded = useRef(false)
  const { id, label, category, note } = input

  useEffect(() => {
    if (recorded.current) {
      return
    }

    recorded.current = true
    recordExtensionProfilerSample({
      id,
      label,
      category,
      kind: 'mount',
      durationMs: performance.now() - mountedAt.current,
      note,
    })
  }, [category, id, label, mountedAt, note])
}

export function useExtensionProfilerSnapshot(): ExtensionProfilerSnapshot {
  const [snapshot, setSnapshot] = useState<ExtensionProfilerSnapshot>(() => getExtensionProfilerSnapshot())

  useEffect(() => {
    const handleStorageUpdate = () => {
      setSnapshot(getExtensionProfilerSnapshot())
    }

    window.addEventListener('ide-profiler:extension-samples', handleStorageUpdate)
    window.addEventListener('storage', handleStorageUpdate)

    return () => {
      window.removeEventListener('ide-profiler:extension-samples', handleStorageUpdate)
      window.removeEventListener('storage', handleStorageUpdate)
    }
  }, [])

  return snapshot
}
