/**
 * session-keepalive.test.ts
 * Unit tests for proactive client-side session refresh
 */

import { getSessionExpiry, scheduleRefresh, doSilentRefresh } from '../session-keepalive';

describe('Session Keepalive', () => {
  let cookieMock: string = '';

  beforeEach(() => {
    // Mock global document cookie
    Object.defineProperty(document, 'cookie', {
      get: () => cookieMock,
      set: (val: string) => { cookieMock = val; },
      configurable: true,
    });
    
    // Mock global fetch
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
    });

    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.clearAllMocks();
    cookieMock = '';
    jest.clearAllTimers();
  });

  test('getSessionExpiry() returns null when cookie is missing', () => {
    expect(getSessionExpiry()).toBeNull();
  });

  test('getSessionExpiry() returns timestamp as milliseconds when cookie is present', () => {
    const mockExpiry = Math.floor(Date.now() / 1000) + 3600; // 1h in future
    document.cookie = `_session_expires=${mockExpiry}; Path=/; SameSite=Lax; Secure`;
    
    const expiry = getSessionExpiry();
    expect(expiry).toBe(mockExpiry * 1000);
  });

  test('scheduleRefresh() schedules a timeout when expiry is in the future', () => {
    const mockExpiry = Math.floor(Date.now() / 1000) + 1200; // 20m in future
    document.cookie = `_session_expires=${mockExpiry}; Path=/; SameSite=Lax; Secure`;
    
    // Threshold is 5m, so refresh at 15m (900s)
    scheduleRefresh();
    
    expect(setTimeout).toHaveBeenCalledTimes(1);
    expect(setTimeout).toHaveBeenLastCalledWith(expect.any(Function), 900000);
  });

  test('scheduleRefresh() triggers immediate refresh if below threshold', () => {
    const mockExpiry = Math.floor(Date.now() / 1000) + 120; // 2m in future (< 5m threshold)
    document.cookie = `_session_expires=${mockExpiry}; Path=/; SameSite=Lax; Secure`;
    
    scheduleRefresh();
    
    // Should trigger fetch
    expect(global.fetch).toHaveBeenCalledWith('/oauth2/userinfo', expect.any(Object));
  });

  test('doSilentRefresh() hits the correct endpoint and re-arms', async () => {
    const mockExpiry = Math.floor(Date.now() / 1000) + 1200; // 20m future
    document.cookie = `_session_expires=${mockExpiry}; Path=/; SameSite=Lax; Secure`;
    
    await doSilentRefresh();
    
    expect(global.fetch).toHaveBeenCalledWith('/oauth2/userinfo', {
      credentials: 'same-origin',
      cache: 'no-store'
    });
    
    // Should have re-armed timer
    expect(setTimeout).toHaveBeenCalled();
  });
});
