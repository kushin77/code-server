// @file        backend/src/services/ai/indexing.ts
// @module      ai
// @description Semantic chunking + incremental async indexing pipeline for repository files.
// @owner       platform
// @status      active

import { createHash } from "node:crypto";

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

type QueueTask = () => Promise<void>;

const DEFAULT_OPTIONS: IndexingOptions = {
  chunkSizeTokens: 800,
  chunkOverlapTokens: 120,
  maxQueueSize: 1000,
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
