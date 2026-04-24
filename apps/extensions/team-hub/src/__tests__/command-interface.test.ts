#!/usr/bin/env node
// @file        apps/extensions/team-hub/src/__tests__/command-interface.test.ts
// @module      extensions/team-hub/command-interface-tests
// @description Tests for KC IDE command parsing
// @owner       collab-9
// @status      active

import { describe, it, expect } from 'vitest';
import { resolveTeamHubCommand } from '../command-interface';

describe('TeamHub command interface', () => {
  it('resolves command aliases', () => {
    expect(resolveTeamHubCommand('open sidebar')).toEqual({
      action: 'open-sidebar',
      description: 'Open the Team Hub sidebar',
    });

    expect(resolveTeamHubCommand('  Refresh   Presence ')).toEqual({
      action: 'refresh-presence',
      description: 'Refresh collaboration presence',
    });
  });

  it('returns undefined for unknown commands', () => {
    expect(resolveTeamHubCommand('launch warp drive')).toBeUndefined();
  });
});