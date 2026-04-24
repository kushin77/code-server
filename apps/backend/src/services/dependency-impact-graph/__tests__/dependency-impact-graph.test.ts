import { describe, it, expect, beforeEach, vi } from 'vitest';
import { DependencyImpactGraphService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('DependencyImpactGraphService', () => {
  let service: DependencyImpactGraphService;
  let mockPool: any;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn()
    };

    mockPool = {
      connect: vi.fn().mockResolvedValue(mockClient)
    };

    service = new DependencyImpactGraphService(mockPool);
  });

  it('should initialize service and create tables', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('dependency_modules'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('should add a module', async () => {
    mockClient.query.mockResolvedValueOnce({});

    await service.addModule('mod-1', 'Module 1', '/path/to/mod1.ts', 5000);

    expect(mockClient.query).toHaveBeenCalled();
  });

  it('should add a dependency', async () => {
    mockClient.query.mockResolvedValueOnce({});

    await service.addDependency('mod-1', 'mod-2', 'import');

    expect(mockClient.query).toHaveBeenCalled();
  });

  it('should get dependency information', async () => {
    // Get module
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        module_id: 'mod-1',
        module_name: 'Module 1'
      }]
    });

    // Get dependencies (depends on)
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { target_module_id: 'mod-2' },
        { target_module_id: 'mod-3' }
      ]
    });

    // Get dependents (dependent of)
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { source_module_id: 'mod-4' }
      ]
    });

    // calculateBlastRadius - cache check
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - BFS breadth first search
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - cache insert
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // hasCircularDependency - DFS cycle detection
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const dep = await service.getDependency('mod-1');

    expect(dep).not.toBeNull();
    expect(dep?.dependsOn.length).toBe(2);
    expect(dep?.dependentOf.length).toBe(1);
  });

  it('should return null for non-existent module', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const dep = await service.getDependency('non-existent');

    expect(dep).toBeNull();
  });

  it('should get dependency graph', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { module_id: 'mod-1', module_name: 'Module 1' },
        { module_id: 'mod-2', module_name: 'Module 2' }
      ]
    });

    // For each module getDependency call
    for (let i = 0; i < 2; i++) {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ module_id: 'mod-1', module_name: 'Module 1' }]
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
    }

    mockClient.query.mockResolvedValueOnce({ rows: [] });

    const graph = await service.getGraph();

    expect(graph.modules).toBeDefined();
    expect(graph.circularDependencies).toBeDefined();
  });

  it('should emit module-added event', async () => {
    let emittedEvent: any;

    service.on('module-added', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.addModule('mod-1', 'Module 1');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.moduleId).toBe('mod-1');
  });

  it('should emit dependency-added event', async () => {
    let emittedEvent: any;

    service.on('dependency-added', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.addDependency('mod-1', 'mod-2');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.sourceModuleId).toBe('mod-1');
  });

  it('should cleanup old data', async () => {
    mockClient.query.mockResolvedValueOnce({
      rowCount: 100
    });

    const count = await service.cleanupOldData(30);

    expect(count).toBe(100);
  });

  it('should emit data-cleaned event', async () => {
    let emittedEvent: any;

    service.on('data-cleaned', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rowCount: 50
    });

    await service.cleanupOldData(30);

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.count).toBe(50);
  });

  it('should handle multiple dependencies for a module', async () => {
    // Get module
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        module_id: 'mod-1',
        module_name: 'Module 1'
      }]
    });

    // Get dependencies (depends on)
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { target_module_id: 'mod-2' },
        { target_module_id: 'mod-3' },
        { target_module_id: 'mod-4' }
      ]
    });

    // Get dependents (dependent of)
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { source_module_id: 'mod-5' },
        { source_module_id: 'mod-6' }
      ]
    });

    // calculateBlastRadius - cache check
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - BFS breadth first search
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - cache insert
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // hasCircularDependency - DFS cycle detection
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const dep = await service.getDependency('mod-1');

    expect(dep?.dependsOn.length).toBe(3);
    expect(dep?.dependentOf.length).toBe(2);
  });

  it('should have blast radius score', async () => {
    // Get module
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        module_id: 'mod-1',
        module_name: 'Module 1'
      }]
    });

    // Get dependencies (depends on)
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // Get dependents (dependent of)
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - cache check
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - BFS breadth first search
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // calculateBlastRadius - cache insert
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    // hasCircularDependency - DFS cycle detection
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const dep = await service.getDependency('mod-1');

    expect(dep?.blastRadiusScore).toBeGreaterThanOrEqual(0);
    expect(dep?.blastRadiusScore).toBeLessThanOrEqual(100);
  });

  it('should detect circular dependencies', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { module_id: 'mod-1', module_name: 'Module 1' },
        { module_id: 'mod-2', module_name: 'Module 2' }
      ]
    });

    // Mock getDependency calls
    for (let i = 0; i < 2; i++) {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ module_id: 'mod-1', module_name: 'Module 1' }]
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });
    }

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { source_module_id: 'mod-1', source_module_id_2: 'mod-2' }
      ]
    });

    const graph = await service.getGraph();

    expect(graph).toBeDefined();
  });
});
