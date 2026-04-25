/**
 * @file apps/copilot-engine/src/memory-persistence.js
 * @module copilot-engine/memory-persistence
 * @description Redis/PostgreSQL backends for durable CopilotMemory state.
 */

const DEFAULT_RETENTION_DAYS = 30;

export class InMemoryPersistenceBackend {
  constructor() {
    this.snapshots = new Map();
  }

  async saveSnapshot(sessionId, snapshot) {
    this.snapshots.set(sessionId, structuredClone(snapshot));
  }

  async loadSnapshot(sessionId) {
    const snapshot = this.snapshots.get(sessionId);
    return snapshot ? structuredClone(snapshot) : null;
  }

  async pruneExpired() {
    // No-op for process-local backend.
  }
}

export class RedisPersistenceBackend {
  /**
   * @param {{client: any, keyPrefix?: string, retentionDays?: number}} options
   */
  constructor(options) {
    this.client = options.client;
    this.keyPrefix = options.keyPrefix ?? "copilot:memory";
    this.retentionDays = options.retentionDays ?? DEFAULT_RETENTION_DAYS;
  }

  _snapshotKey(sessionId) {
    return `${this.keyPrefix}:snapshot:${sessionId}`;
  }

  _indexKey() {
    return `${this.keyPrefix}:sessions`;
  }

  async saveSnapshot(sessionId, snapshot) {
    const key = this._snapshotKey(sessionId);
    const payload = JSON.stringify(snapshot);
    const ttlSeconds = this.retentionDays * 24 * 60 * 60;

    if (typeof this.client.set === "function") {
      await this.client.set(key, payload, { EX: ttlSeconds });
    } else {
      await this.client.sendCommand(["SET", key, payload, "EX", `${ttlSeconds}`]);
    }

    const now = Date.now();
    if (typeof this.client.zAdd === "function") {
      await this.client.zAdd(this._indexKey(), [{ score: now, value: sessionId }]);
    } else {
      await this.client.sendCommand([
        "ZADD",
        this._indexKey(),
        `${now}`,
        sessionId,
      ]);
    }
  }

  async loadSnapshot(sessionId) {
    const key = this._snapshotKey(sessionId);
    const raw =
      typeof this.client.get === "function"
        ? await this.client.get(key)
        : await this.client.sendCommand(["GET", key]);

    return raw ? JSON.parse(raw) : null;
  }

  async pruneExpired() {
    const cutoff = Date.now() - this.retentionDays * 24 * 60 * 60 * 1000;
    const indexKey = this._indexKey();

    const stale =
      typeof this.client.zRangeByScore === "function"
        ? await this.client.zRangeByScore(indexKey, 0, cutoff)
        : await this.client.sendCommand([
            "ZRANGEBYSCORE",
            indexKey,
            "0",
            `${cutoff}`,
          ]);

    for (const sessionId of stale ?? []) {
      const key = this._snapshotKey(sessionId);
      if (typeof this.client.del === "function") {
        await this.client.del(key);
      } else {
        await this.client.sendCommand(["DEL", key]);
      }
    }

    if (typeof this.client.zRemRangeByScore === "function") {
      await this.client.zRemRangeByScore(indexKey, 0, cutoff);
    } else {
      await this.client.sendCommand([
        "ZREMRANGEBYSCORE",
        indexKey,
        "0",
        `${cutoff}`,
      ]);
    }
  }
}

export class PostgresPersistenceBackend {
  /**
   * @param {{client: any, schema?: string, retentionDays?: number}} options
   */
  constructor(options) {
    this.client = options.client;
    this.schema = options.schema ?? "public";
    this.retentionDays = options.retentionDays ?? DEFAULT_RETENTION_DAYS;
  }

  _table(name) {
    return `${this.schema}.${name}`;
  }

  async ensureSchema() {
    await this.client.query(`
      CREATE TABLE IF NOT EXISTS ${this._table("copilot_memory_snapshots")} (
        session_id TEXT PRIMARY KEY,
        snapshot JSONB NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    await this.client.query(`
      CREATE INDEX IF NOT EXISTS idx_copilot_memory_snapshots_updated_at
      ON ${this._table("copilot_memory_snapshots")} (updated_at DESC);
    `);
  }

  async saveSnapshot(sessionId, snapshot) {
    await this.ensureSchema();
    await this.client.query(
      `
      INSERT INTO ${this._table("copilot_memory_snapshots")} (session_id, snapshot, updated_at)
      VALUES ($1, $2::jsonb, NOW())
      ON CONFLICT (session_id)
      DO UPDATE SET snapshot = EXCLUDED.snapshot, updated_at = NOW();
      `,
      [sessionId, JSON.stringify(snapshot)]
    );
  }

  async loadSnapshot(sessionId) {
    await this.ensureSchema();
    const res = await this.client.query(
      `
      SELECT snapshot
      FROM ${this._table("copilot_memory_snapshots")}
      WHERE session_id = $1
      ORDER BY updated_at DESC
      LIMIT 1;
      `,
      [sessionId]
    );
    return res.rows[0]?.snapshot ?? null;
  }

  async pruneExpired() {
    await this.ensureSchema();
    await this.client.query(
      `
      DELETE FROM ${this._table("copilot_memory_snapshots")}
      WHERE updated_at < NOW() - ($1::INT * INTERVAL '1 day');
      `,
      [this.retentionDays]
    );
  }
}

/**
 * Build backend from env configuration.
 * Supported MEMORY_BACKEND: memory | redis | postgres
 */
export async function createMemoryPersistenceBackendFromEnv(options = {}) {
  const backend = (process.env.MEMORY_BACKEND ?? "memory").toLowerCase();
  const retentionDays = Number(
    process.env.MEMORY_RETENTION_DAYS ?? options.retentionDays ?? DEFAULT_RETENTION_DAYS
  );

  if (backend === "memory") {
    return new InMemoryPersistenceBackend();
  }

  if (backend === "redis") {
    const redisUrl = process.env.REDIS_URL;
    const redisPkg = await import("redis");
    const client = options.client ?? redisPkg.createClient({ url: redisUrl });
    if (typeof client.connect === "function") {
      await client.connect();
    }
    return new RedisPersistenceBackend({ client, retentionDays });
  }

  if (backend === "postgres") {
    const pgPkg = await import("pg");
    const connectionString = process.env.DATABASE_URL;
    const client = options.client ?? new pgPkg.Client({ connectionString });
    if (typeof client.connect === "function") {
      await client.connect();
    }
    return new PostgresPersistenceBackend({ client, retentionDays });
  }

  throw new Error(`Unsupported MEMORY_BACKEND: ${backend}`);
}
