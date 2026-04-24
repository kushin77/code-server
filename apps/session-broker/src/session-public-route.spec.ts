import { describe, expect, it } from 'vitest';
import { buildSessionPublicUrl, stripSessionPublicRoutePrefix } from './session-public-route.js';

describe('session public route helpers', () => {
  it('builds a public session URL from the configured base URL', () => {
    expect(buildSessionPublicUrl('https://dev.kushnir.cloud/', 'session-123')).toBe(
      'https://dev.kushnir.cloud/s/session-123',
    );
  });

  it('strips the public route prefix while preserving nested paths and queries', () => {
    expect(stripSessionPublicRoutePrefix('/s/session-123/editor/file.ts?tab=1', 'session-123')).toBe(
      '/editor/file.ts?tab=1',
    );
  });

  it('normalizes the root route to slash', () => {
    expect(stripSessionPublicRoutePrefix('/s/session-123', 'session-123')).toBe('/');
  });
});
