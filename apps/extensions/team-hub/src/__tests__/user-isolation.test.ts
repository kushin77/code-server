#!/usr/bin/env node
// @file        apps/extensions/team-hub/src/__tests__/user-isolation.test.ts
// @module      extensions/team-hub/user-isolation-tests
// @description Tests for KC IDE user isolation behavior
// @owner       collab-9
// @status      active

import { describe, it, expect } from 'vitest';
import { applyUserIsolation } from '../user-isolation';
import type { TeamHubSnapshot } from '../types';

const snapshot: TeamHubSnapshot = {
  currentUser: {
    id: 'you',
    displayName: 'You',
    status: 'online',
    lastSeen: 1,
  },
  users: [
    { id: 'alice', displayName: 'Alice', status: 'online', lastSeen: 1 },
    { id: 'bob', displayName: 'Bob', status: 'away', lastSeen: 1 },
  ],
  groupedUsers: {
    online: [{ id: 'alice', displayName: 'Alice', status: 'online', lastSeen: 1 }],
    away: [{ id: 'bob', displayName: 'Bob', status: 'away', lastSeen: 1 }],
    offline: []
  },
  sameFileUsers: [{ id: 'alice', displayName: 'Alice', status: 'online', lastSeen: 1 }],
  updatedAt: 1,
};

describe('user isolation', () => {
  it('keeps collaborators visible in shared mode', () => {
    const shared = applyUserIsolation(snapshot, false);
    expect(shared.users).toHaveLength(2);
    expect(shared.sameFileUsers).toHaveLength(1);
  });

  it('hides collaborator data in private view', () => {
    const isolated = applyUserIsolation(snapshot, true);
    expect(isolated.users).toHaveLength(0);
    expect(isolated.groupedUsers.online).toHaveLength(0);
    expect(isolated.sameFileUsers).toHaveLength(0);
    expect(isolated.currentUser.displayName).toBe('You');
  });
});