/**
 * ws-session-handoff.ts
 * Graceful WebSocket session hand-off during cookie rotation
 * Part of Phase 2 Session Self-Healing (#335)
 */

interface SessionHandoffOptions {
  ws: WebSocket;
  onReconnect: (newWs: WebSocket) => void;
  maxRetries?: number;
}

/**
 * Orchestrates a graceful WebSocket hand-off when a session refresh is detected.
 * Prevents terminal/process loss by synchronizing the reconnect with the new cookie.
 */
export async function performWSSessionHandoff({
  ws,
  onReconnect,
  maxRetries = 3
}: SessionHandoffOptions): Promise<void> {
  console.debug('[WS-Handoff] Initiating session hand-off for WebSocket...');

  try {
    // 1. Signal server to prepare for hand-off (drain/buffer mode)
    // Only if the protocol supports it - fall back to immediate reconnect if not
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'session_handoff_prepare' }));
    }

    // 2. Wait a brief moment for server to acknowledge or finish in-flight I/O
    await new Promise(resolve => setTimeout(resolve, 300));

    // 3. Close the current connection
    // Code 1000 = Normal Closure
    ws.close(1000, 'session_refresh_handoff');

    // 4. Reconnect with the fresh cookie (browser sends the updated cookie automatically)
    let retryCount = 0;
    const reconnect = () => {
      const newWs = new WebSocket(ws.url, ws.protocol);
      
      newWs.onopen = () => {
        console.debug('[WS-Handoff] Successfully reconnected with fresh session');
        // 5. Signal server to resume from buffer
        newWs.send(JSON.stringify({ type: 'session_handoff_resume' }));
        onReconnect(newWs);
      };

      newWs.onerror = () => {
        if (retryCount < maxRetries) {
          retryCount++;
          const delay = Math.pow(2, retryCount) * 1000;
          console.warn(`[WS-Handoff] Reconnect failed, retrying in ${delay}ms...`);
          setTimeout(reconnect, delay);
        } else {
          console.error('[WS-Handoff] Critical: WebSocket failed to reconnect after session rotation');
          // Fall back to showing a UI banner for manual reconnect
        }
      };
    };

    reconnect();

  } catch (error) {
    console.error('[WS-Handoff] Error during WebSocket session hand-off:', error);
    // Attempt fallback reconnect
    onReconnect(new WebSocket(ws.url, ws.protocol));
  }
}

/**
 * Hook to inject into the session refresh cycle
 * Whenever any tab refreshes (via BroadcastChannel), trigger hand-off for any active WS
 */
export function setupWSAutoHandoff(getActiveWS: () => WebSocket | null, updateWS: (newWs: WebSocket) => void): void {
  if (typeof BroadcastChannel === 'undefined') return;

  const channel = new BroadcastChannel('code-server-session');
  channel.onmessage = (event) => {
    if (event.data.type === 'SESSION_REFRESHED') {
      const currentWs = getActiveWS();
      if (currentWs && currentWs.readyState === WebSocket.OPEN) {
        performWSSessionHandoff({
          ws: currentWs,
          onReconnect: (newWs) => updateWS(newWs)
        });
      }
    }
  };
}
