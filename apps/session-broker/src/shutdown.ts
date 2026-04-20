// @file        apps/session-broker/src/shutdown.ts
// @module      session-management/shutdown
// @description Graceful shutdown handler for session-broker service
//              Ensures spawned containers are stopped, sessions are notified,
//              and state is persisted before process termination.
//

import { Logger } from 'winston';

export interface ShutdownDependencies {
  sessionManager: {
    stopAcceptingNewSessions(): void;
    notifyShutdown(): Promise<void>;
    waitForSessionsToSave(maxWaitMs: number): Promise<void>;
    close(): Promise<void>;
    listActiveSessions(): Array<{ id: string; containerId?: string }>;
  };
  containerManager: {
    stopAllContainers(options: { timeout?: number }): Promise<void>;
  };
  logger: Logger;
  server?: {
    close(): Promise<void>;
  };
}

const GRACEFUL_SHUTDOWN_TIMEOUT_MS = 30_000; // 30 seconds
const SESSION_SAVE_GRACE_PERIOD_MS = 10_000; // 10 seconds for sessions to save

/**
 * Set up graceful shutdown handlers for SIGTERM, SIGINT, and uncaught errors
 * Ensures:
 * 1. New sessions are rejected
 * 2. Active sessions are notified of shutdown
 * 3. Sessions are given time to save state
 * 4. Spawned containers are stopped gracefully
 * 5. Database connections are closed
 * 6. Process exits cleanly
 */
export function setupGracefulShutdown(
  deps: ShutdownDependencies
): void {
  let isShuttingDown = false;

  const performShutdown = async (signal: string, code?: number): Promise<void> => {
    if (isShuttingDown) {
      deps.logger.warn('Shutdown already in progress, ignoring signal', { signal });
      return;
    }

    isShuttingDown = true;
    deps.logger.info(`Received ${signal}, starting graceful shutdown...`, { signal });

    const shutdownPromise = (async () => {
      try {
        // Step 1: Stop accepting new sessions
        deps.logger.info('Stopping new session acceptance...');
        deps.sessionManager.stopAcceptingNewSessions();

        // Step 2: Notify active sessions of impending shutdown
        deps.logger.info('Notifying active sessions of shutdown...');
        const activeSessions = deps.sessionManager.listActiveSessions();
        deps.logger.info(`Found ${activeSessions.length} active sessions`, {
          sessionCount: activeSessions.length,
        });

        try {
          await deps.sessionManager.notifyShutdown();
        } catch (error) {
          deps.logger.warn('Failed to notify some sessions', {
            error: error instanceof Error ? error.message : String(error),
          });
        }

        // Step 3: Wait for graceful termination
        deps.logger.info('Waiting for sessions to save state...');
        try {
          await deps.sessionManager.waitForSessionsToSave(SESSION_SAVE_GRACE_PERIOD_MS);
        } catch (error) {
          deps.logger.warn('Session save-state wait interrupted', {
            error: error instanceof Error ? error.message : String(error),
          });
        }

        // Step 4: Stop HTTP server
        if (deps.server) {
          deps.logger.info('Closing HTTP server...');
          try {
            await deps.server.close();
          } catch (error) {
            deps.logger.warn('HTTP server close failed', {
              error: error instanceof Error ? error.message : String(error),
            });
          }
        }

        // Step 5: Stop spawned containers
        deps.logger.info('Stopping spawned containers...');
        try {
          await deps.containerManager.stopAllContainers({ timeout: 10 });
        } catch (error) {
          deps.logger.error('Container shutdown failed', {
            error: error instanceof Error ? error.message : String(error),
          });
        }

        // Step 6: Close database connections
        deps.logger.info('Closing database connections...');
        try {
          await deps.sessionManager.close();
        } catch (error) {
          deps.logger.warn('Database close failed', {
            error: error instanceof Error ? error.message : String(error),
          });
        }

        deps.logger.info('Graceful shutdown complete');
      } catch (error) {
        deps.logger.error('Shutdown sequence failed', {
          error: error instanceof Error ? error.message : String(error),
        });
        throw error;
      }
    })();

    // Force exit after timeout
    const timeoutPromise = new Promise<void>((_resolve, reject) => {
      setTimeout(() => {
        const msg = `Shutdown timeout after ${GRACEFUL_SHUTDOWN_TIMEOUT_MS}ms, forcing exit`;
        deps.logger.error(msg);
        reject(new Error(msg));
      }, GRACEFUL_SHUTDOWN_TIMEOUT_MS);
    });

    try {
      await Promise.race([shutdownPromise, timeoutPromise]);
      deps.logger.info('Shutdown sequence completed successfully', { signal });
      process.exit(code ?? 0);
    } catch (error) {
      deps.logger.error('Shutdown failed, forcing exit', {
        error: error instanceof Error ? error.message : String(error),
        signal,
      });
      process.exit(code ?? 1);
    }
  };

  // Handle termination signals
  process.on('SIGTERM', () => void performShutdown('SIGTERM', 0));
  process.on('SIGINT', () => void performShutdown('SIGINT', 0));

  // Handle uncaught errors
  process.on('uncaughtException', (error: Error) => {
    deps.logger.error('Uncaught exception', {
      message: error.message,
      stack: error.stack,
    });
    void performShutdown('uncaughtException', 1);
  });

  process.on('unhandledRejection', (reason: unknown) => {
    deps.logger.error('Unhandled rejection', {
      reason: reason instanceof Error ? reason.message : String(reason),
    });
    void performShutdown('unhandledRejection', 1);
  });
}
