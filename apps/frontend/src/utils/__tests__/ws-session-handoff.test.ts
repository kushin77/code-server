/**
 * ws-session-handoff.test.ts
 * Unit tests for WebSocket session hand-off logic
 */

import { performWSSessionHandoff } from '../ws-session-handoff';

// Mock global WebSocket
class MockWebSocket {
  url: string;
  protocol: string;
  readyState: number = 1; // OPEN
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  send: jest.Mock = jest.fn();
  close: jest.Mock = jest.fn(() => (this.readyState = 3)); // CLOSED

  constructor(url: string, protocol: string = '') {
    this.url = url;
    this.protocol = protocol;
    // Auto-open new connections to simulate success
    setTimeout(() => {
      if (this.onopen) this.onopen();
    }, 0);
  }
}

global.WebSocket = MockWebSocket as any;

describe('WS Session Handoff', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.clearAllMocks();
    jest.clearAllTimers();
  });

  test('performWSSessionHandoff() sends handoff_prepare signal', async () => {
    const mockWS = new MockWebSocket('ws://localhost:8080');
    const onReconnect = jest.fn();
    
    // Use clear manual control for async
    const handoff = performWSSessionHandoff({
      ws: mockWS as any as WebSocket,
      onReconnect
    });
    
    // In-flight before timers
    expect(mockWS.send).toHaveBeenCalledWith(JSON.stringify({ type: 'session_handoff_prepare' }));
    
    // Advance time for handoff process
    jest.advanceTimersByTime(1000);
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
    
    jest.advanceTimersByTime(1000);
    await handoff;
    
    // The second WS created should have sent the resume signal
    expect(lastWs.send).toHaveBeenCalledWith(JSON.stringify({ type: 'session_handoff_resume' }));
  });
});
