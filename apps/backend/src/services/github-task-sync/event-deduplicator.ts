#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/event-deduplicator.ts
// @module      services/github-task-sync/event-deduplicator
// @description Deduplicates GitHub webhook events to prevent duplicate processing
// @owner       collab-9
// @status      active

import { getLogger } from '../../utils/logger';

const logger = getLogger('EventDeduplicator');

export interface DeduplicationOptions {
  ttlMs?: number; // Time-to-live for dedup cache (default: 24 hours)
  maxEntries?: number; // Maximum cache entries (default: 10000)
}

export interface CachedEvent {
  eventId: string;
  timestamp: number;
  action: string;
  issueNumber?: number;
}

/**
 * Event Deduplicator
 * Prevents processing of duplicate webhook events
 * Uses LRU cache with TTL for memory efficiency
 */
export class EventDeduplicator {
  private cache: Map<string, CachedEvent> = new Map();
  private options: Required<DeduplicationOptions>;
  private cleanupInterval: NodeJS.Timer | null = null;

  constructor(options: DeduplicationOptions = {}) {
    this.options = {
      ttlMs: options.ttlMs || 24 * 60 * 60 * 1000, // 24 hours
      maxEntries: options.maxEntries || 10000,
    };

    // Start periodic cleanup
    this.startCleanup();
  }

  /**
   * Check if event has been seen before
   * Returns true if event is duplicate (already cached)
   */
  isDuplicate(eventId: string): boolean {
    const cached = this.cache.get(eventId);

    if (!cached) {
      return false;
    }

    // Check if cached entry has expired
    const age = Date.now() - cached.timestamp;
    if (age > this.options.ttlMs) {
      this.cache.delete(eventId);
      return false;
    }

    logger.debug('Duplicate event detected', {
      eventId,
      action: cached.action,
      issue: cached.issueNumber,
    });

    return true;
  }

  /**
   * Record event in dedup cache
   */
  recordEvent(
    eventId: string,
    action: string,
    issueNumber?: number
  ): void {
    // Evict oldest entry if cache is full (simple LRU)
    if (this.cache.size >= this.options.maxEntries) {
      const firstKey = this.cache.keys().next().value;
      if (firstKey) {
        this.cache.delete(firstKey);
        logger.debug('Cache evicted oldest entry', { eventId: firstKey });
      }
    }

    this.cache.set(eventId, {
      eventId,
      timestamp: Date.now(),
      action,
      issueNumber,
    });

    logger.debug('Event recorded in dedup cache', {
      eventId,
      action,
      issue: issueNumber,
      cacheSize: this.cache.size,
    });
  }

  /**
   * Check and record in one operation
   * Returns true if event is new (not a duplicate)
   */
  checkAndRecord(
    eventId: string,
    action: string,
    issueNumber?: number
  ): boolean {
    const isNew = !this.isDuplicate(eventId);

    if (isNew) {
      this.recordEvent(eventId, action, issueNumber);
    }

    return isNew;
  }

  /**
   * Get dedup cache stats
   */
  getStats(): {
    cacheSize: number;
    maxEntries: number;
    ttlMs: number;
  } {
    return {
      cacheSize: this.cache.size,
      maxEntries: this.options.maxEntries,
      ttlMs: this.options.ttlMs,
    };
  }

  /**
   * Start periodic cleanup of expired entries
   */
  private startCleanup(): void {
    // Run cleanup every 5 minutes
    this.cleanupInterval = setInterval(() => {
      this.cleanup();
    }, 5 * 60 * 1000);

    // Don't keep the process alive just for cleanup
    if (this.cleanupInterval.unref) {
      this.cleanupInterval.unref();
    }
  }

  /**
   * Clean up expired entries from cache
   */
  private cleanup(): void {
    const now = Date.now();
    let removed = 0;

    for (const [key, event] of this.cache.entries()) {
      const age = now - event.timestamp;
      if (age > this.options.ttlMs) {
        this.cache.delete(key);
        removed++;
      }
    }

    if (removed > 0) {
      logger.debug('Cleanup removed expired entries', {
        removed,
        remaining: this.cache.size,
      });
    }
  }

  /**
   * Dispose and stop cleanup interval
   */
  dispose(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
    this.cache.clear();
  }
}

export default EventDeduplicator;