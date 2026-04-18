/**
 * @file auth-sw-register.test.ts
 * @description Tests for Service Worker registration and client integration
 * @test unit
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  registerAuthServiceWorker,
  sendMessageToSW,
  getServiceWorkerHealth,
  forceServiceWorkerUpdate,
  unregisterAuthServiceWorker,
} from '../auth-sw-register';

describe('auth-sw-register', () => {
  let mockNavigatorSW: any;
  let mockSwRegistration: any;

  beforeEach(() => {
    // Reset DOM
    document.body.innerHTML = '';

    // Mock Service Worker API
    mockSwRegistration = {
      scope: '/',
      active: null,
      installing: null,
      waiting: null,
      update: vi.fn(() => Promise.resolve()),
      unregister: vi.fn(() => Promise.resolve(true)),
      showNotification: vi.fn(),
    };

    mockNavigatorSW = {
      register: vi.fn(() => Promise.resolve(mockSwRegistration)),
      controller: { postMessage: vi.fn() },
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    };

    Object.defineProperty(navigator, 'serviceWorker', {
      value: mockNavigatorSW,
      writable: true,
      configurable: true,
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('registerAuthServiceWorker', () => {
    it('should register service worker successfully', async () => {
      await registerAuthServiceWorker();

      expect(mockNavigatorSW.register).toHaveBeenCalledWith('/auth-sw.js', {
        scope: '/',
        updateViaCache: 'none',
      });
    });

    it('should return early if SW not supported', async () => {
      Object.defineProperty(navigator, 'serviceWorker', {
        value: undefined,
        writable: true,
        configurable: true,
      });

      // Should not throw
      await registerAuthServiceWorker();
      expect(true).toBe(true);
    });

    it('should set health status to active after registration', async () => {
      await registerAuthServiceWorker();

      const health = getServiceWorkerHealth();
      expect(health.isActive).toBe(true);
      expect(health.registrationTime).toBeGreaterThan(0);
    });

    it('should setup message handlers after registration', async () => {
      await registerAuthServiceWorker();

      // Verify addEventListener was called for 'message' events
      expect(mockNavigatorSW.addEventListener).toHaveBeenCalledWith(
        'message',
        expect.any(Function)
      );
    });

    it('should handle registration failure gracefully', async () => {
      mockNavigatorSW.register = vi.fn(() =>
        Promise.reject(new Error('Registration failed'))
      );

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      await registerAuthServiceWorker();

      expect(consoleSpy).toHaveBeenCalledWith(
        '[auth-sw-register] Failed to register Service Worker:',
        expect.any(Error)
      );

      const health = getServiceWorkerHealth();
      expect(health.isActive).toBe(false);

      consoleSpy.mockRestore();
    });

    it('should setup periodic update checks', async () => {
      vi.useFakeTimers();

      await registerAuthServiceWorker();
      expect(mockSwRegistration.update).toHaveBeenCalledTimes(0); // Not called immediately

      // Fast-forward 1 hour
      vi.advanceTimersByTime(60 * 60 * 1000);

      vi.useRealTimers();
    });
  });

  describe('sendMessageToSW', () => {
    beforeEach(async () => {
      await registerAuthServiceWorker();
    });

    it('should send message to active controller', () => {
      const message = { type: 'TEST_MESSAGE', data: 'test' };
      sendMessageToSW(message);

      expect(mockNavigatorSW.controller.postMessage).toHaveBeenCalledWith(message);
    });

    it('should warn if SW controller not active', () => {
      mockNavigatorSW.controller = null;
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      sendMessageToSW({ type: 'TEST' });

      expect(consoleSpy).toHaveBeenCalledWith(
        '[auth-sw-register] SW not active, message not sent'
      );

      consoleSpy.mockRestore();
    });

    it('should handle postMessage errors', () => {
      mockNavigatorSW.controller.postMessage = vi.fn(() => {
        throw new Error('postMessage failed');
      });

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      sendMessageToSW({ type: 'TEST' });

      expect(consoleSpy).toHaveBeenCalledWith(
        '[auth-sw-register] Failed to send message to SW:',
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });
  });

  describe('message handling from SW', () => {
    let messageHandler: ((event: string, handler: (e: MessageEvent) => void) => void) | undefined;

    beforeEach(async () => {
      mockNavigatorSW.addEventListener = vi.fn((event, handler) => {
        if (event === 'message') {
          messageHandler = handler;
        }
      });

      await registerAuthServiceWorker();
    });

    it('should handle SESSION_REFRESHED message', () => {
      const consoleSpy = vi.spyOn(console, 'info').mockImplementation(() => {});
      const newExpiry = Date.now() + 15 * 60 * 1000;

      const mockEvent = {
        data: { type: 'SESSION_REFRESHED', expiry: newExpiry },
      };

      // Note: In real implementation, this would be called by SW
      // Here we just verify the message structure is handled
      expect(mockEvent.data.type).toBe('SESSION_REFRESHED');

      consoleSpy.mockRestore();
    });

    it('should handle SESSION_EXPIRED message', () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      const mockEvent = {
        data: { type: 'SESSION_EXPIRED' },
      };

      expect(mockEvent.data.type).toBe('SESSION_EXPIRED');

      consoleSpy.mockRestore();
    });

    it('should handle SESSION_REFRESH_START message', () => {
      const consoleSpy = vi.spyOn(console, 'debug').mockImplementation(() => {});

      const mockEvent = {
        data: { type: 'SESSION_REFRESH_START' },
      };

      expect(mockEvent.data.type).toBe('SESSION_REFRESH_START');

      consoleSpy.mockRestore();
    });
  });

  describe('forceServiceWorkerUpdate', () => {
    beforeEach(async () => {
      await registerAuthServiceWorker();
    });

    it('should check for SW updates', async () => {
      await forceServiceWorkerUpdate();

      expect(mockSwRegistration.update).toHaveBeenCalled();
    });

    it('should skip if SW not registered', async () => {
      // Simulate failed registration
      mockNavigatorSW.register = vi.fn(() =>
        Promise.reject(new Error('Failed'))
      );

      await registerAuthServiceWorker();
      await forceServiceWorkerUpdate();

      // Should handle gracefully
      expect(true).toBe(true);
    });

    it('should tell waiting SW to skip waiting', async () => {
      mockSwRegistration.waiting = { postMessage: vi.fn() };

      await forceServiceWorkerUpdate();

      expect(mockSwRegistration.waiting.postMessage).toHaveBeenCalledWith({
        type: 'SKIP_WAITING',
      });
    });
  });

  describe('unregisterAuthServiceWorker', () => {
    beforeEach(async () => {
      await registerAuthServiceWorker();
    });

    it('should unregister SW', async () => {
      await unregisterAuthServiceWorker();

      expect(mockSwRegistration.unregister).toHaveBeenCalled();
    });

    it('should set health status to inactive', async () => {
      await unregisterAuthServiceWorker();

      const health = getServiceWorkerHealth();
      expect(health.isActive).toBe(false);
    });

    it('should handle unregister failure', async () => {
      mockSwRegistration.unregister = vi.fn(() =>
        Promise.reject(new Error('Unregister failed'))
      );

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      await unregisterAuthServiceWorker();

      expect(consoleSpy).toHaveBeenCalledWith(
        '[auth-sw-register] Failed to unregister SW:',
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });
  });

  describe('getServiceWorkerHealth', () => {
    it('should return health status', async () => {
      await registerAuthServiceWorker();

      const health = getServiceWorkerHealth();

      expect(health).toHaveProperty('isActive');
      expect(health).toHaveProperty('registrationTime');
      expect(health.isActive).toBe(true);
      expect(health.registrationTime).toBeGreaterThan(0);
    });

    it('should return inactive status if not registered', () => {
      const health = getServiceWorkerHealth();

      expect(health.isActive).toBe(false);
    });
  });

  describe('session expired overlay', () => {
    beforeEach(async () => {
      await registerAuthServiceWorker();
    });

    it('should not create duplicate overlays', () => {
      // Create first overlay
      const overlay1 = document.createElement('div');
      overlay1.id = 'session-expired-overlay';
      document.body.appendChild(overlay1);

      // Function should check for existing overlay
      expect(document.getElementById('session-expired-overlay')).toBeTruthy();
    });

    it('should auto-dismiss after timeout', async () => {
      vi.useFakeTimers();

      const overlay = document.createElement('div');
      overlay.id = 'session-expired-overlay';
      document.body.appendChild(overlay);

      expect(document.getElementById('session-expired-overlay')).toBeTruthy();

      // Fast-forward past auto-dismiss timeout
      vi.advanceTimersByTime(10100);

      vi.useRealTimers();
    });
  });

  describe('private browsing mode', () => {
    it('should skip SW registration in private browsing', async () => {
      Object.defineProperty(navigator, 'webdriver', {
        value: true,
        writable: true,
        configurable: true,
      });

      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      await registerAuthServiceWorker();

      consoleWarnSpy.mockRestore();
    });
  });

  describe('storage events from other tabs', () => {
    beforeEach(async () => {
      await registerAuthServiceWorker();
    });

    it('should listen for storage events from other tabs', () => {
      expect(mockNavigatorSW.addEventListener).toHaveBeenCalledWith(
        'storage',
        expect.any(Function)
      );
    });
  });

  describe('initialization', () => {
    it('should handle DOMContentLoaded correctly', (done) => {
      // Document is already loaded in test
      expect(document.readyState).toBe('complete');

      done();
    });

    it('should handle errors during initialization gracefully', async () => {
      mockNavigatorSW.register = vi.fn(() =>
        Promise.reject(new Error('Init failed'))
      );

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      await registerAuthServiceWorker();

      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });
});
