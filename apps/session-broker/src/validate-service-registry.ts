// @file        apps/session-broker/validate-service-registry.ts
// @module      session-management/scaling/validation
// @description Validation script for service registry functionality
//
// Simple validation to ensure the service registry compiles and basic functionality works.

import { ServiceRegistry, type ServiceRegistryConfig } from './service-registry.js';

async function validateServiceRegistry() {
  console.log('Validating Service Registry...');

  const config: ServiceRegistryConfig = {
    redisUrls: ['redis://localhost:6379'],
    instanceId: 'validation-instance',
    instanceHost: 'localhost',
    instancePort: 5000,
    heartbeatIntervalMs: 5000,
    instanceTimeoutMs: 15000,
    registryKey: 'validation:service-registry'
  };

  const registry = new ServiceRegistry(config);

  try {
    // Test basic functionality without Redis
    console.log('✓ ServiceRegistry class instantiated');

    const stats = registry.getStats();
    console.log('✓ getStats() works:', stats.instanceId);

    const sessionId = 'test-session-123';
    const isResponsible = registry.isResponsibleForSession(sessionId);
    console.log('✓ isResponsibleForSession() works:', isResponsible);

    const instance = registry.getInstanceForSession(sessionId);
    console.log('✓ getInstanceForSession() works:', instance?.id || 'null');

    console.log('✓ Service Registry validation passed');
  } catch (error) {
    console.error('✗ Service Registry validation failed:', error);
    process.exit(1);
  } finally {
    await registry.stop();
  }
}

validateServiceRegistry().catch(console.error);