/**
 * Performance profiling utilities for extensions
 * Provides hooks and utilities for measuring extension performance
 */

import { useCallback, useRef, useEffect } from 'react'

export interface PerformanceMetric {
  id: string
  label: string
  category: string
  kind: 'load' | 'interaction' | 'render'
  startTime: number
  endTime?: number
  duration?: number
  memory?: {
    before: number
    after: number
    peak: number
  }
}

const metrics: Map<string, PerformanceMetric> = new Map()

/**
 * Hook to mount a performance profiler for an extension
 */
export function useExtensionMountProfiler(config: {
  id: string
  label: string
  category: string
  kind: 'load' | 'interaction' | 'render'
}): void {
  useEffect(() => {
    const metric: PerformanceMetric = {
      ...config,
      startTime: performance.now(),
    }
    metrics.set(config.id, metric)

    return () => {
      const m = metrics.get(config.id)
      if (m) {
        m.endTime = performance.now()
        m.duration = m.endTime - m.startTime
      }
    }
  }, [config])
}

/**
 * Measure an async operation
 */
export async function measureAsyncExtensionProfiler<T>(
  config: {
    id: string
    label: string
    category: string
    kind: 'load' | 'interaction' | 'render'
  },
  fn: () => Promise<T>
): Promise<T> {
  const startTime = performance.now()
  const metric: PerformanceMetric = {
    ...config,
    startTime,
  }

  try {
    const result = await fn()
    metric.endTime = performance.now()
    metric.duration = metric.endTime - metric.startTime
    metrics.set(config.id, metric)
    return result
  } catch (error) {
    metric.endTime = performance.now()
    metric.duration = metric.endTime - metric.startTime
    metrics.set(config.id, metric)
    throw error
  }
}

/**
 * Get all recorded metrics
 */
export function getAllMetrics(): PerformanceMetric[] {
  return Array.from(metrics.values())
}

/**
 * Clear all metrics
 */
export function clearMetrics(): void {
  metrics.clear()
}

/**
 * Get metrics for a specific extension
 */
export function getMetricsForExtension(extensionId: string): PerformanceMetric[] {
  return Array.from(metrics.values()).filter((m) => m.id.startsWith(extensionId))
}
