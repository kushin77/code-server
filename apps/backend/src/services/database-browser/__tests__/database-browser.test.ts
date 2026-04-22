import { describe, it, expect, beforeEach, vi } from 'vitest';
import { DatabaseBrowserService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('DatabaseBrowserService', () => {
  let service: DatabaseBrowserService;
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

    service = new DatabaseBrowserService(mockPool);
  });

  it('should initialize service and create tables', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('query_history'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('should get postgres schema', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ table_name: 'users' }, { table_name: 'posts' }]
    });

    // Mock for first table
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { column_name: 'id', data_type: 'integer', is_nullable: 'NO', column_default: null },
        { column_name: 'name', data_type: 'varchar', is_nullable: 'YES', column_default: null }
      ]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ attname: 'id' }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 100 }]
    });

    // Mock for second table
    mockClient.query.mockResolvedValueOnce({
      rows: [{ column_name: 'id', data_type: 'integer', is_nullable: 'NO', column_default: null }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ attname: 'id' }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 50 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ table_name: 'user_views', view_definition: 'SELECT * FROM users' }]
    });

    const schema = await service.getPostgresSchema('mydb');

    expect(schema.databaseType).toBe('PostgreSQL');
    expect(schema.tables.length).toBe(2);
  });

  it('should execute a query', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: 1, name: 'Test' }],
      rowCount: 1,
      fields: [{ name: 'id' }, { name: 'name' }]
    });

    mockClient.query.mockResolvedValueOnce({});

    const result = await service.executeQuery('SELECT * FROM users', 'PostgreSQL', 'mydb');

    expect(result.rows.length).toBe(1);
    expect(result.executionTime).toBeGreaterThanOrEqual(0);
  });

  it('should save a query', async () => {
    mockClient.query.mockResolvedValueOnce({});

    await service.saveQuery('My Query', 'SELECT * FROM users', 'PostgreSQL');

    expect(mockClient.query).toHaveBeenCalled();
  });

  it('should get saved queries', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { id: '1', query_name: 'Query 1', query_text: 'SELECT * FROM users', database_type: 'PostgreSQL', created_at: new Date() }
      ]
    });

    const queries = await service.getSavedQueries();

    expect(queries.length).toBe(1);
    expect(queries[0].query_name).toBe('Query 1');
  });

  it('should export query results as CSV', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: 1, name: 'John' }, { id: 2, name: 'Jane' }],
      fields: [{ name: 'id' }, { name: 'name' }]
    });

    mockClient.query.mockResolvedValueOnce({});

    const csv = await service.exportQueryResults('SELECT * FROM users', 'csv', 'PostgreSQL');

    expect(csv).toContain('id,name');
    expect(csv).toContain('1');
    expect(csv).toContain('John');
  });

  it('should export query results as JSON', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: 1, name: 'John' }],
      fields: [{ name: 'id' }, { name: 'name' }]
    });

    mockClient.query.mockResolvedValueOnce({});

    const json = await service.exportQueryResults('SELECT * FROM users', 'json', 'PostgreSQL');

    expect(json).toContain('id');
    expect(json).toContain('John');
  });

  it('should get query history', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { id: '1', query_text: 'SELECT * FROM users', execution_time_ms: 100, row_count: 50, error_message: null, executed_at: new Date() }
      ]
    });

    const history = await service.getQueryHistory('PostgreSQL');

    expect(history.length).toBe(1);
    expect(history[0].execution_time_ms).toBe(100);
  });

  it('should autocomplete table names', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ table_name: 'users' }, { table_name: 'user_roles' }]
    });

    const tables = await service.autocompleteTableNames('PostgreSQL', 'user');

    expect(tables.length).toBe(2);
    expect(tables[0]).toBe('users');
  });

  it('should autocomplete column names', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ column_name: 'id' }, { column_name: 'name' }]
    });

    const columns = await service.autocompleteColumnNames('PostgreSQL', 'users');

    expect(columns.length).toBe(2);
    expect(columns[0]).toBe('id');
  });

  it('should cleanup old query history', async () => {
    mockClient.query.mockResolvedValueOnce({
      rowCount: 200
    });

    const count = await service.cleanupOldQueryHistory(30);

    expect(count).toBe(200);
  });

  it('should emit query-executed event', async () => {
    let emittedEvent: any;

    service.on('query-executed', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [],
      rowCount: 0,
      fields: []
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.executeQuery('SELECT 1', 'PostgreSQL', 'mydb');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.databaseType).toBe('PostgreSQL');
  });

  it('should emit query-saved event', async () => {
    let emittedEvent: any;

    service.on('query-saved', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.saveQuery('Test Query', 'SELECT 1', 'PostgreSQL');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.queryName).toBe('Test Query');
  });

  it('should emit export-completed event', async () => {
    let emittedEvent: any;

    service.on('export-completed', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: 1 }],
      fields: [{ name: 'id' }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.exportQueryResults('SELECT 1', 'csv', 'PostgreSQL');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.format).toBe('csv');
  });

  it('should emit history-cleaned event', async () => {
    let emittedEvent: any;

    service.on('history-cleaned', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rowCount: 100
    });

    await service.cleanupOldQueryHistory(30);

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.count).toBe(100);
  });

  it('should get saved queries for specific user', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { id: '1', query_name: 'User Query', query_text: 'SELECT * FROM users', database_type: 'PostgreSQL', created_at: new Date() }
      ]
    });

    const queries = await service.getSavedQueries('user-123');

    expect(queries.length).toBe(1);
    expect(queries[0].query_name).toBe('User Query');
  });

  it('should handle query with no results', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [],
      rowCount: 0,
      fields: [{ name: 'id' }]
    });

    mockClient.query.mockResolvedValueOnce({});

    const result = await service.executeQuery('SELECT * FROM users WHERE id = 999', 'PostgreSQL', 'mydb');

    expect(result.rows.length).toBe(0);
    expect(result.rowCount).toBe(0);
  });

  it('should record query in history on execution', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: 1, name: 'Test' }],
      rowCount: 1,
      fields: [{ name: 'id' }, { name: 'name' }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.executeQuery('SELECT * FROM users', 'PostgreSQL', 'mydb');

    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO query_history'),
      expect.any(Array)
    );
  });
});
