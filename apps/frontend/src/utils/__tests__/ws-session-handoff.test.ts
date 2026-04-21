/**
 * ws-session-handoff.test.ts
 * Unit tests for WebSocket session hand-off logic
 */

import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import { performWSSessionHandoff } from '../ws-session-handoff';

// Mock global WebSocket — onopen fires synchronously via setter (no fake-timer dependency)
class MockWebSocket {
  static OPEN = 1;
  static CLOSED = 3;
  url: string;
  protocol: string;
  readyState: number = 1; // OPEN
  private _onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  send: ReturnType<typeof vi.fn> = vi.fn();
  close: ReturnType<typeof vi.fn> = vi.fn(() => (this.readyState = 3)); // CLOSED

  constructor(url: string, protocol: string = '') {
    this.url = url;
    this.protocol = protocol;
  }

  set onopen(cb: (() => void) | null) {
    this._onopen = cb;
    // Auto-fire open event synchronously when handler is registered (simulates immediate connection)
    if (cb && this.readyState === MockWebSocket.OPEN) {
      cb();
    }
  }

  get onopen() {
    return this._onopen;
  }
}

global.WebSocket = MockWebSocket as any;

describe('WS Session Handoff', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.clearAllTimers();
  });

  test('performWSSessionHandoff() sends handoff_prepare signal', async () => {
    const mockWS = new MockWebSocket('ws://localhost:8080');
    const onReconnect = vi.fn();
    
    // Use clear manual control for async
    const handoff = performWSSessionHandoff({
      ws: mockWS as any as WebSocket,
      onReconnect
    });
    
    // In-flight before timers
    expect(mockWS.send).toHaveBeenCalledWith(JSON.stringify({ type: 'session_handoff_prepare' }));
    
    // Advance time for handoff process
    vi.advanceTimersByTime(1000);
    await handoff;
    
    expect(mockWS.close).toHaveBeenCalledWith(1000, 'session_refresh_handoff');
    expect(onReconnect).toHaveBeenCalled();
  });

  test('performWSSessionHandoff() sends handoff_resume after reconnect', async () => {
    const mockWS = new MockWebSocket('ws://localhost:8080');
    let lastWs: any = null;
    const onReconnect = (newWs: WebSocket) => {
      lastWs = newWs;
    };
    
    const handoff = performWSSessionHandoff({
      ws: mockWS as any as WebSocket,
      onReconnect
    });
    
    vi.advanceTimersByTime(1000);
    await handoff;
    
    // The second WS created should have sent the resume signal
    expect(lastWs.send).toHaveBeenCalledWith(JSON.stringify({ type: 'session_handoff_resume' }));
  });
});
