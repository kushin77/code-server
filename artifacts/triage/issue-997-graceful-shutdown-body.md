## P1: Implement Graceful Shutdown for session-broker and Spawned Containers

### Problem

**File**: `apps/session-broker/src/index.ts`

The session-broker spawns per-user code-server containers but has **no SIGTERM/SIGINT handler** to gracefully terminate user sessions during:
- Host shutdown
- Service restart
- Rolling deployment
- Scaling down

### Impact

1. **User work loss**: Unsaved buffers in code-server are lost on abrupt termination
2. **Orphaned containers**: Spawned containers may continue running after broker dies
3. **Database inconsistency**: Session records may not be cleaned up
4. **Connection leaks**: WebSocket connections left hanging

### Current Behavior

```typescript
// NO shutdown handling in current code:
// - No process.on('SIGTERM', ...)
// - No process.on('SIGINT', ...)
// - No cleanup of spawned containers
// - No session state persistence
```

### Required Changes

#### 1. Add Shutdown Handler

```typescript
// apps/session-broker/src/shutdown.ts

import { Logger } from './logger';
import { SessionManager } from './session-manager';
import { ContainerManager } from './container-manager';

const GRACEFUL_SHUTDOWN_TIMEOUT_MS = 30000; // 30 seconds

export function setupGracefulShutdown(
  sessionManager: SessionManager,
  containerManager: ContainerManager,
  logger: Logger
) {
  let isShuttingDown = false;

  const shutdown = async (signal: string) => {
    if (isShuttingDown) {
      logger.warn('Shutdown already in progress, ignoring signal');
      return;
    }
    isShuttingDown = true;
    logger.info(`Received ${signal}, starting graceful shutdown...`);

    const shutdownPromise = (async () => {
      // Step 1: Stop accepting new sessions
      logger.info('Stopping new session acceptance...');
      sessionManager.stopAcceptingNewSessions();

      // Step 2: Notify active sessions of impending shutdown
      logger.info('Notifying active sessions...');
      await sessionManager.notifyShutdown();

      // Step 3: Wait for graceful termination
      logger.info('Waiting for sessions to save state...');
      await sessionManager.waitForSessionsToSave(10000);

      // Step 4: Stop spawned containers
      logger.info('Stopping spawned containers...');
      await containerManager.stopAllContainers({ timeout: 10 });

      // Step 5: Close database connections
      logger.info('Closing database connections...');
      await sessionManager.close();

      // Step 6: Exit
      logger.info('Graceful shutdown complete');
    })();

    // Force exit after timeout
    const timeoutPromise = new Promise<void>((_, reject) => {
      setTimeout(() => {
        logger.error(`Shutdown timeout after ${GRACEFUL_SHUTDOWN_TIMEOUT_MS}ms, forcing exit`);
        reject(new Error('Shutdown timeout'));
      }, GRACEFUL_SHUTDOWN_TIMEOUT_MS);
    });

    try {
      await Promise.race([shutdownPromise, timeoutPromise]);
      process.exit(0);
    } catch (error) {
      logger.error('Shutdown failed:', error);
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('uncaughtException', (error) => {
    logger.error('Uncaught exception:', error);
    shutdown('uncaughtException');
  });
  process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled rejection:', reason);
    shutdown('unhandledRejection');
  });
}
```

#### 2. Container Manager Stop Method

```typescript
// apps/session-broker/src/container-manager.ts

class ContainerManager {
  async stopAllContainers(options: { timeout?: number } = {}): Promise<void> {
    const timeout = options.timeout ?? 10;
    const containers = await this.listManagedContainers();
    
    const stopPromises = containers.map(async (container) => {
      try {
        await container.stop({ t: timeout });
        this.logger.info(`Stopped container ${container.id}`);
      } catch (error) {
        this.logger.error(`Failed to stop container ${container.id}:`, error);
        // Force kill if stop fails
        await container.kill().catch(() => {});
      }
    });

    await Promise.allSettled(stopPromises);
  }

  async listManagedContainers(): Promise<Container[]> {
    return this.docker.listContainers({
      filters: { label: ['managed-by=session-broker'] }
    });
  }
}
```

#### 3. Session Save-State

```typescript
// apps/session-broker/src/session-manager.ts

class SessionManager {
  async notifyShutdown(): Promise<void> {
    for (const session of this.activeSessions.values()) {
      try {
        // Send shutdown notification via WebSocket
        await session.ws?.send(JSON.stringify({
          type: 'shutdown_warning',
          message: 'Server is shutting down. Please save your work.',
          gracePeriodMs: 10000
        }));
      } catch (error) {
        this.logger.warn(`Failed to notify session ${session.id}`);
      }
    }
  }

  async waitForSessionsToSave(maxWaitMs: number): Promise<void> {
    const deadline = Date.now() + maxWaitMs;
    while (this.activeSessions.size > 0 && Date.now() < deadline) {
      await new Promise(r => setTimeout(r, 500));
    }
  }
}
```

#### 4. Docker Compose Stop Config

```yaml
# docker-compose.yml:
session-broker:
  stop_grace_period: 30s
  stop_signal: SIGTERM
```

### Validation

```bash
# Test graceful shutdown
docker-compose stop session-broker

# Check logs for shutdown sequence
docker-compose logs session-broker | tail -20

# Expected output:
# Received SIGTERM, starting graceful shutdown...
# Stopping new session acceptance...
# Notifying active sessions...
# Stopping spawned containers...
# Graceful shutdown complete
```

### Definition of Done

- [ ] `setupGracefulShutdown()` function implemented
- [ ] Container stop-all logic implemented
- [ ] Session notification on shutdown
- [ ] docker-compose.yml has `stop_grace_period: 30s`
- [ ] Orphaned container cleanup tested
- [ ] User notification visible in IDE
- [ ] Logs show full shutdown sequence

### Cross-References

- Related: #969 (Root containers)
- Related: #974 (session-broker hardening)
