// @file        apps/frontend/src/extensions/__tests__/otel-apm-sidebar.test.ts
// @module      extensions/otel-apm-sidebar/tests
// @description Unit tests for OpenTelemetry APM sidebar

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { OtelApmSidebarProvider } from '../otel-apm-sidebar';

describe('OtelApmSidebarProvider', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('initializes provider', () => {
    expect(OtelApmSidebarProvider).toBeDefined();
  });

  it('supports tree data provider methods', () => {
    expect(typeof OtelApmSidebarProvider.prototype.getChildren).toBe('function');
    expect(typeof OtelApmSidebarProvider.prototype.getTreeItem).toBe('function');
  });

  it('supports refresh lifecycle', () => {
    expect(typeof OtelApmSidebarProvider.prototype.refresh).toBe('function');
  });

  it('supports dispose lifecycle', () => {
    expect(typeof OtelApmSidebarProvider.prototype.dispose).toBe('function');
  });
});
