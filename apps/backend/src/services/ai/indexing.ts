// @file        backend/src/services/ai/indexing.ts
// @module      ai
// @description Semantic chunking + incremental async indexing pipeline for repository files.
// @owner       platform
// @status      active

import { createHash } from "node:crypto";
import { watch, type FSWatcher } from "node:fs";

export type SupportedLanguage = "python" | "typescript" | "go" | "rust" | "java" | "unknown";

export interface RepositoryFile {
  path: string;
  content: string;
  updatedAt?: number;
}

export interface ChunkMetadata {
  filePath: string;
  language: SupportedLanguage;
  symbol: string;
  startLine: number;
  endLine: number;
  contentHash: string;
}

export interface RepositoryChunk {
  id: string;
  content: string;
  tokenCount: number;
  metadata: ChunkMetadata;
}

export interface IndexingOptions {
  chunkSizeTokens: number;
  chunkOverlapTokens: number;
  maxQueueSize: number;
}

export interface IndexingResult {
  indexedFiles: number;
  indexedChunks: number;
  deduplicatedChunks: number;
  queueDepth: number;
}

export interface SearchResult {
  chunk: RepositoryChunk;
  score: number;
}

export interface RetrievalBenchmarkCase {
  query: string;
  expectedFilePaths: string[];
}

export interface RetrievalQualityMetrics {
  totalCases: number;
  hitRate: number;
  precision: number;
  recall: number;
  avgLatencyMs: number;
  p95LatencyMs: number;
}

export interface IncrementalIndexingLatencyMetrics {
  changedFiles: number;
  avgLatencyMs: number;
  p95LatencyMs: number;
  maxLatencyMs: number;
  under100msRate: number;
}

export interface FileWatcherEvent {
  eventType: "change" | "rename";
  filePath: string;
  indexed: boolean;
}

export interface FileWatcherOptions {
  debounceMs: number;
}

type QueueTask = () => Promise<void>;

const DEFAULT_OPTIONS: IndexingOptions = {
  chunkSizeTokens: 800,
  chunkOverlapTokens: 120,
  maxQueueSize: 1000,
};

const DEFAULT_FILE_WATCHER_OPTIONS: FileWatcherOptions = {
  debounceMs: 80,
};

interface SymbolBoundary {
  symbol: string;
  startLine: number;
  endLine: number;
}

export class RepositoryIndexer {
  private readonly options: IndexingOptions;
  private readonly chunksById = new Map<string, RepositoryChunk>();
  private readonly chunkHashToId = new Map<string, string>();
  private readonly fileHash = new Map<string, string>();

  private readonly queue: QueueTask[] = [];
  private queueActive = false;

  constructor(options?: Partial<IndexingOptions>) {
    this.options = {
      ...DEFAULT_OPTIONS,
      ...options,
    };
  }

  async indexRepository(files: RepositoryFile[]): Promise<IndexingResult> {
    let indexedFiles = 0;

    for (const file of files) {
      await this.enqueue(async () => {
        const changed = this.indexFileInternal(file);
        if (changed) {
          indexedFiles += 1;
        }
      });
    }

    return {
      indexedFiles,
      indexedChunks: this.chunksById.size,
      deduplicatedChunks: this.chunkHashToId.size - this.chunksById.size,
      queueDepth: this.queue.length,
    };
  }

  async reindexChangedFile(file: RepositoryFile): Promise<boolean> {
    let changed = false;

    await this.enqueue(async () => {
      changed = this.indexFileInternal(file);
    });

    return changed;
  }

  async processFileChange(path: string, content: string): Promise<boolean> {
    return this.reindexChangedFile({ path, content, updatedAt: Date.now() });
  }

  getQueueDepth(): number {
    return this.queue.length;
  }

  getAllChunks(): RepositoryChunk[] {
    return Array.from(this.chunksById.values());
  }

  search(query: string, limit = 10): SearchResult[] {
    const q = tokenize(query.toLowerCase());
    if (q.length === 0) return [];

    const scored = this.getAllChunks().map((chunk) => {
      const hay = tokenize(chunk.content.toLowerCase());
      const overlap = q.filter((term) => hay.includes(term)).length;
      const score = overlap / q.length;
      return { chunk, score };
    });

    return scored
      .filter((s) => s.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);
  }

  private async enqueue(task: QueueTask): Promise<void> {
    if (this.queue.length >= this.options.maxQueueSize) {
      throw new Error(`Index queue is full (${this.options.maxQueueSize})`);
    }

    this.queue.push(task);
    await this.drainQueue();
  }

  private async drainQueue(): Promise<void> {
    if (this.queueActive) return;
    this.queueActive = true;

    try {
      while (this.queue.length > 0) {
        const task = this.queue.shift();
        if (!task) continue;
        await task();
      }
    } finally {
      this.queueActive = false;
    }
  }

  private indexFileInternal(file: RepositoryFile): boolean {
    const language = inferLanguage(file.path);
    const fileContentHash = hash(file.content);

    if (this.fileHash.get(file.path) === fileContentHash) {
      return false;
    }

    this.removeChunksForFile(file.path);

    const boundaries = semanticBoundaries(file.content, language);
    const created = this.buildChunks(file.path, file.content, language, boundaries);

    for (const chunk of created) {
      if (this.chunkHashToId.has(chunk.metadata.contentHash)) {
        continue;
      }
      this.chunkHashToId.set(chunk.metadata.contentHash, chunk.id);
      this.chunksById.set(chunk.id, chunk);
    }

    this.fileHash.set(file.path, fileContentHash);
    return true;
  }

  private removeChunksForFile(filePath: string): void {
    for (const [id, chunk] of this.chunksById.entries()) {
      if (chunk.metadata.filePath === filePath) {
        this.chunksById.delete(id);
        this.chunkHashToId.delete(chunk.metadata.contentHash);
      }
    }
  }

  private buildChunks(
    filePath: string,
    content: string,
    language: SupportedLanguage,
    boundaries: SymbolBoundary[],
  ): RepositoryChunk[] {
    const lines = content.split(/\r?\n/);
    const chunks: RepositoryChunk[] = [];

    for (const boundary of boundaries) {
      const raw = lines.slice(boundary.startLine - 1, boundary.endLine).join("\n");
      const windows = chunkByTokenWindow(raw, this.options.chunkSizeTokens, this.options.chunkOverlapTokens);

      let segment = 0;
      for (const windowContent of windows) {
        const tokenCount = estimateTokenCount(windowContent);
        const contentHash = hash(windowContent);
        const id = hash(`${filePath}:${boundary.symbol}:${segment}:${contentHash}`).slice(0, 16);

        chunks.push({
          id,
          content: windowContent,
          tokenCount,
          metadata: {
            filePath,
            language,
            symbol: boundary.symbol,
            startLine: boundary.startLine,
            endLine: boundary.endLine,
            contentHash,
          },
        });
        segment += 1;
      }
    }

    return chunks;
  }
}

export function inferLanguage(filePath: string): SupportedLanguage {
  const lower = filePath.toLowerCase();
  if (lower.endsWith(".py")) return "python";
  if (lower.endsWith(".ts") || lower.endsWith(".tsx") || lower.endsWith(".js")) return "typescript";
  if (lower.endsWith(".go")) return "go";
  if (lower.endsWith(".rs")) return "rust";
  if (lower.endsWith(".java")) return "java";
  return "unknown";
}

export function semanticBoundaries(content: string, language: SupportedLanguage): SymbolBoundary[] {
  const lines = content.split(/\r?\n/);
  if (lines.length === 0) {
    return [{ symbol: "file", startLine: 1, endLine: 1 }];
  }

  const starts = detectSymbolStarts(lines, language);
  if (starts.length === 0) {
    return [{ symbol: "file", startLine: 1, endLine: lines.length }];
  }

  const boundaries: SymbolBoundary[] = [];
  for (let i = 0; i < starts.length; i += 1) {
    const current = starts[i];
    const next = starts[i + 1];
    boundaries.push({
      symbol: current.symbol,
      startLine: current.line,
      endLine: next ? Math.max(current.line, next.line - 1) : lines.length,
    });
  }

  return boundaries;
}

function detectSymbolStarts(lines: string[], language: SupportedLanguage): Array<{ symbol: string; line: number }> {
  const starts: Array<{ symbol: string; line: number }> = [];

  const patternByLanguage: Record<SupportedLanguage, RegExp[]> = {
    python: [/^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/, /^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:(]/],
    typescript: [
      /^\s*export\s+class\s+([A-Za-z_][A-Za-z0-9_]*)/,
      /^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)/,
      /^\s*export\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/,
      /^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/,
      /^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(?.*=>/,
    ],
    go: [/^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/, /^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)\s+struct\s*\{/],
    rust: [/^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/, /^\s*impl\s+([A-Za-z_][A-Za-z0-9_:<>]*)/],
    java: [
      /^\s*(public\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)/,
      /^\s*(public|private|protected)?\s*(static\s+)?[A-Za-z0-9_<>,\[\]]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/,
    ],
    unknown: [],
  };

  const patterns = patternByLanguage[language] || [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    for (const pattern of patterns) {
      const match = line.match(pattern);
      if (!match) continue;
      const name = (match[3] || match[2] || match[1] || "symbol").trim();
      starts.push({ symbol: name, line: i + 1 });
      break;
    }
  }

  return starts;
}

export function chunkByTokenWindow(content: string, chunkSizeTokens: number, overlapTokens: number): string[] {
  const words = tokenize(content);
  if (words.length === 0) return [""];

  const chunks: string[] = [];
  let cursor = 0;
  const step = Math.max(1, chunkSizeTokens - overlapTokens);

  while (cursor < words.length) {
    const end = Math.min(words.length, cursor + chunkSizeTokens);
    const windowWords = words.slice(cursor, end);
    chunks.push(windowWords.join(" "));
    if (end === words.length) break;
    cursor += step;
  }

  return chunks;
}

export function evaluateRetrievalQuality(
  indexer: RepositoryIndexer,
  cases: RetrievalBenchmarkCase[],
  limit = 5,
): RetrievalQualityMetrics {
  if (cases.length === 0) {
    return {
      totalCases: 0,
      hitRate: 0,
      precision: 0,
      recall: 0,
      avgLatencyMs: 0,
      p95LatencyMs: 0,
    };
  }

  let hits = 0;
  let totalTp = 0;
  let totalFp = 0;
  let totalFn = 0;
  const latencies: number[] = [];

  for (const testCase of cases) {
    const started = process.hrtime.bigint();
    const results = indexer.search(testCase.query, limit);
    const elapsedNs = process.hrtime.bigint() - started;
    latencies.push(Number(elapsedNs) / 1_000_000);

    const predicted = new Set(results.map((r) => r.chunk.metadata.filePath));
    const expected = new Set(testCase.expectedFilePaths);

    let tp = 0;
    for (const file of predicted) {
      if (expected.has(file)) tp += 1;
    }

    const fp = Math.max(0, predicted.size - tp);
    const fn = Math.max(0, expected.size - tp);

    totalTp += tp;
    totalFp += fp;
    totalFn += fn;
    if (tp > 0) hits += 1;
  }

  const avgLatencyMs = latencies.reduce((acc, v) => acc + v, 0) / latencies.length;
  const sorted = [...latencies].sort((a, b) => a - b);
  const p95Index = Math.max(0, Math.ceil(sorted.length * 0.95) - 1);
  const p95LatencyMs = sorted[p95Index] ?? 0;

  const precisionDenominator = totalTp + totalFp;
  const recallDenominator = totalTp + totalFn;

  return {
    totalCases: cases.length,
    hitRate: hits / cases.length,
    precision: precisionDenominator > 0 ? totalTp / precisionDenominator : 0,
    recall: recallDenominator > 0 ? totalTp / recallDenominator : 0,
    avgLatencyMs,
    p95LatencyMs,
  };
}

export async function evaluateIncrementalIndexingLatency(
  indexer: RepositoryIndexer,
  changedFiles: RepositoryFile[],
): Promise<IncrementalIndexingLatencyMetrics> {
  if (changedFiles.length === 0) {
    return {
      changedFiles: 0,
      avgLatencyMs: 0,
      p95LatencyMs: 0,
      maxLatencyMs: 0,
      under100msRate: 0,
    };
  }

  const latencies: number[] = [];
  let under100msCount = 0;

  for (const file of changedFiles) {
    const started = process.hrtime.bigint();
    await indexer.reindexChangedFile(file);
    const elapsedNs = process.hrtime.bigint() - started;
    const elapsedMs = Number(elapsedNs) / 1_000_000;
    latencies.push(elapsedMs);
    if (elapsedMs < 100) {
      under100msCount += 1;
    }
  }

  const avgLatencyMs = latencies.reduce((acc, v) => acc + v, 0) / latencies.length;
  const sorted = [...latencies].sort((a, b) => a - b);
  const p95Index = Math.max(0, Math.ceil(sorted.length * 0.95) - 1);
  const p95LatencyMs = sorted[p95Index] ?? 0;

  return {
    changedFiles: changedFiles.length,
    avgLatencyMs,
    p95LatencyMs,
    maxLatencyMs: sorted[sorted.length - 1] ?? 0,
    under100msRate: under100msCount / changedFiles.length,
  };
}

export function formatRetrievalQualityPrometheus(metrics: RetrievalQualityMetrics): string {
  return [
    "# HELP indexing_retrieval_hit_rate Retrieval benchmark hit-rate.",
    "# TYPE indexing_retrieval_hit_rate gauge",
    `indexing_retrieval_hit_rate ${metrics.hitRate}`,
    "# HELP indexing_retrieval_precision Retrieval benchmark precision.",
    "# TYPE indexing_retrieval_precision gauge",
    `indexing_retrieval_precision ${metrics.precision}`,
    "# HELP indexing_retrieval_recall Retrieval benchmark recall.",
    "# TYPE indexing_retrieval_recall gauge",
    `indexing_retrieval_recall ${metrics.recall}`,
    "# HELP indexing_retrieval_latency_ms_p95 Retrieval benchmark p95 query latency in milliseconds.",
    "# TYPE indexing_retrieval_latency_ms_p95 gauge",
    `indexing_retrieval_latency_ms_p95 ${metrics.p95LatencyMs}`,
  ].join("\n");
}

export function isIndexablePath(filePath: string): boolean {
  return inferLanguage(filePath) !== "unknown";
}

export function startRepositoryFileWatcher(
  rootPath: string,
  indexer: RepositoryIndexer,
  readFile: (path: string) => Promise<string>,
  onEvent?: (event: FileWatcherEvent) => void,
  options?: Partial<FileWatcherOptions>,
): FSWatcher {
  const watcherOptions: FileWatcherOptions = {
    ...DEFAULT_FILE_WATCHER_OPTIONS,
    ...options,
  };

  const pending = new Map<string, ReturnType<typeof setTimeout>>();

  const flushPath = (filePath: string, eventType: "change" | "rename"): void => {
    const existing = pending.get(filePath);
    if (existing) {
      clearTimeout(existing);
    }

    pending.set(
      filePath,
      setTimeout(() => {
        pending.delete(filePath);

        if (!isIndexablePath(filePath)) {
          return;
        }

        void readFile(filePath)
          .then((content) => indexer.processFileChange(filePath, content))
          .then((indexed) => onEvent?.({ eventType, filePath, indexed }))
          .catch(() => {
            onEvent?.({ eventType, filePath, indexed: false });
          });
      }, watcherOptions.debounceMs),
    );
  };

  const watcher = watch(rootPath, { recursive: true }, (eventType, fileName) => {
    if (!fileName) {
      return;
    }
    if (eventType !== "change" && eventType !== "rename") {
      return;
    }
    flushPath(fileName.toString(), eventType);
  });

  watcher.on("close", () => {
    for (const timer of pending.values()) {
      clearTimeout(timer);
    }
    pending.clear();
  });

  return watcher;
}

function estimateTokenCount(content: string): number {
  return tokenize(content).length;
}

function tokenize(content: string): string[] {
  return content
    .split(/\s+/)
    .map((x) => x.trim())
    .filter((x) => x.length > 0);
}

function hash(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}
