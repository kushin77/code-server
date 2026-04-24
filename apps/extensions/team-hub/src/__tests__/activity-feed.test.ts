#!/usr/bin/env node
// @file        apps/extensions/team-hub/src/__tests__/activity-feed.test.ts
// @module      extensions/team-hub/activity-feed-tests
// @description Tests for Team Hub activity feed rendering and retention
// @owner       collab-9
// @status      active

import { describe, it, expect } from 'vitest';
import {
  MAX_ACTIVITY_ENTRIES,
  createActivityEntry,
  prependActivityEntry,
  renderActivityFeedHtml,
} from '../activity-feed';

describe('TeamHub activity feed', () => {
  it('keeps only the newest bounded set of entries', () => {
    let entries = [] as ReturnType<typeof createActivityEntry>[];

    for (let index = 0; index < MAX_ACTIVITY_ENTRIES + 2; index++) {
      entries = prependActivityEntry(
        entries,
        createActivityEntry('collaboration', `Item ${index}`, undefined, 1_000 + index)
      );
    }

    expect(entries).toHaveLength(MAX_ACTIVITY_ENTRIES);
    expect(entries[0].title).toBe('Item 9');
    expect(entries[entries.length - 1].title).toBe('Item 2');
  });

  it('escapes activity content in rendered html', () => {
    const html = renderActivityFeedHtml([
      createActivityEntry('system', '<script>alert(1)</script>', 'shared & ready', 1_000),
    ], new Date(61_000));

    expect(html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(html).toContain('shared &amp; ready');
    expect(html).toContain('1m ago');
  });
});