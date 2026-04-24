/**
 * ws-session-handoff.test.ts
 * Unit tests for WebSocket session hand-off logic
 */
import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import { performWSSessionHandoff } from '../ws-session-handoff';
// Mock global WebSocket — onopen fires synchronously via setter (no fake-timer dependency)
class MockWebSocket {
    constructor(url, protocol = '') {
        this.readyState = 1; // OPEN
        this._onopen = null;
        this.onclose = null;
        this.onerror = null;
        this.send = vi.fn();
        this.close = vi.fn(() => (this.readyState = 3)); // CLOSED
        this.url = url;
        this.protocol = protocol;
    }
    set onopen(cb) {
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
MockWebSocket.OPEN = 1;
MockWebSocket.CLOSED = 3;
global.WebSocket = MockWebSocket;
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
            ws: mockWS,
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
        let lastWs = null;
        const onReconnect = (newWs) => {
            lastWs = newWs;
        };
        const handoff = performWSSessionHandoff({
            ws: mockWS,
            onReconnect
        });
        vi.advanceTimersByTime(1000);
        await handoff;
        // The second WS created should have sent the resume signal
        expect(lastWs.send).toHaveBeenCalledWith(JSON.stringify({ type: 'session_handoff_resume' }));
    });
});
//# sourceMappingURL=ws-session-handoff.test.js.map