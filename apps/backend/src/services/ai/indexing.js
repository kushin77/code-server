// @file        backend/src/services/ai/indexing.ts
// @module      ai
// @description Semantic chunking + incremental async indexing pipeline for repository files.
// @owner       platform
// @status      active
import { createHash } from "node:crypto";
import { watch } from "node:fs";
import { getAuditService } from "../audit/audit-service";
const DEFAULT_OPTIONS = {
    chunkSizeTokens: 800,
    chunkOverlapTokens: 120,
    maxQueueSize: 1000,
};
const DEFAULT_FILE_WATCHER_OPTIONS = {
    debounceMs: 80,
};
export class RepositoryIndexer {
    constructor(options) {
        this.chunksById = new Map();
        this.chunkHashToId = new Map();
        this.fileHash = new Map();
        this.queue = [];
        this.queueActive = false;
        this.options = {
            ...DEFAULT_OPTIONS,
            ...options,
        };
    }
    async indexRepository(files) {
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
    async reindexChangedFile(file) {
        let changed = false;
        await this.enqueue(async () => {
            changed = this.indexFileInternal(file);
        });
        return changed;
    }
    async processFileChange(path, content) {
        return this.reindexChangedFile({ path, content, updatedAt: Date.now() });
    }
    getQueueDepth() {
        return this.queue.length;
    }
    getAllChunks() {
        return Array.from(this.chunksById.values());
    }
    search(query, limit = 10) {
        const q = tokenize(query.toLowerCase());
        if (q.length === 0)
            return [];
        // For multi-term queries, require stronger overlap to reduce noisy matches.
        const minOverlap = q.length >= 2 ? 2 : 1;
        const scored = this.getAllChunks().map((chunk) => {
            const hay = tokenize(chunk.content.toLowerCase());
            const overlap = q.filter((term) => hay.includes(term)).length;
            const score = overlap / q.length;
            return { chunk, score, overlap };
        });
        return scored
            .filter((s) => s.overlap >= minOverlap)
            .sort((a, b) => b.score - a.score)
            .map(({ chunk, score }) => ({ chunk, score }))
            .slice(0, limit);
    }
    async enqueue(task) {
        if (this.queue.length >= this.options.maxQueueSize) {
            throw new Error(`Index queue is full (${this.options.maxQueueSize})`);
        }
        this.queue.push(task);
        await this.drainQueue();
    }
    async drainQueue() {
        if (this.queueActive)
            return;
        this.queueActive = true;
        try {
            while (this.queue.length > 0) {
                const task = this.queue.shift();
                if (!task)
                    continue;
                await task();
            }
        }
        finally {
            this.queueActive = false;
        }
    }
    indexFileInternal(file) {
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
    removeChunksForFile(filePath) {
        for (const [id, chunk] of this.chunksById.entries()) {
            if (chunk.metadata.filePath === filePath) {
                this.chunksById.delete(id);
                this.chunkHashToId.delete(chunk.metadata.contentHash);
            }
        }
    }
    buildChunks(filePath, content, language, boundaries) {
        const lines = content.split(/\r?\n/);
        const chunks = [];
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
export function inferLanguage(filePath) {
    const lower = filePath.toLowerCase();
    if (lower.endsWith(".py"))
        return "python";
    if (lower.endsWith(".ts") || lower.endsWith(".tsx") || lower.endsWith(".js"))
        return "typescript";
    if (lower.endsWith(".go"))
        return "go";
    if (lower.endsWith(".rs"))
        return "rust";
    if (lower.endsWith(".java"))
        return "java";
    return "unknown";
}
export function semanticBoundaries(content, language) {
    const lines = content.split(/\r?\n/);
    if (lines.length === 0) {
        return [{ symbol: "file", startLine: 1, endLine: 1 }];
    }
    const starts = detectSymbolStarts(lines, language);
    if (starts.length === 0) {
        return [{ symbol: "file", startLine: 1, endLine: lines.length }];
    }
    const boundaries = [];
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
function detectSymbolStarts(lines, language) {
    const starts = [];
    const patternByLanguage = {
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
            if (!match)
                continue;
            const name = (match[3] || match[2] || match[1] || "symbol").trim();
            starts.push({ symbol: name, line: i + 1 });
            break;
        }
    }
    return starts;
}
export function chunkByTokenWindow(content, chunkSizeTokens, overlapTokens) {
    const words = tokenize(content);
    if (words.length === 0)
        return [""];
    const chunks = [];
    let cursor = 0;
    const step = Math.max(1, chunkSizeTokens - overlapTokens);
    while (cursor < words.length) {
        const end = Math.min(words.length, cursor + chunkSizeTokens);
        const windowWords = words.slice(cursor, end);
        chunks.push(windowWords.join(" "));
        if (end === words.length)
            break;
        cursor += step;
    }
    return chunks;
}
export function evaluateRetrievalQuality(indexer, cases, limit = 5) {
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
    const latencies = [];
    for (const testCase of cases) {
        const started = process.hrtime.bigint();
        const results = indexer.search(testCase.query, limit);
        const elapsedNs = process.hrtime.bigint() - started;
        latencies.push(Number(elapsedNs) / 1000000);
        const predicted = new Set(results.map((r) => r.chunk.metadata.filePath));
        const expected = new Set(testCase.expectedFilePaths);
        let tp = 0;
        for (const file of predicted) {
            if (expected.has(file))
                tp += 1;
        }
        const fp = Math.max(0, predicted.size - tp);
        const fn = Math.max(0, expected.size - tp);
        totalTp += tp;
        totalFp += fp;
        totalFn += fn;
        if (tp > 0)
            hits += 1;
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
export async function evaluateIncrementalIndexingLatency(indexer, changedFiles) {
    if (changedFiles.length === 0) {
        return {
            changedFiles: 0,
            avgLatencyMs: 0,
            p95LatencyMs: 0,
            maxLatencyMs: 0,
            under100msRate: 0,
        };
    }
    const latencies = [];
    let under100msCount = 0;
    for (const file of changedFiles) {
        const started = process.hrtime.bigint();
        await indexer.reindexChangedFile(file);
        const elapsedNs = process.hrtime.bigint() - started;
        const elapsedMs = Number(elapsedNs) / 1000000;
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
export function formatRetrievalQualityPrometheus(metrics) {
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
export function isIndexablePath(filePath) {
    return inferLanguage(filePath) !== "unknown";
}
export function startRepositoryFileWatcher(rootPath, indexer, readFile, onEvent, options) {
    const watcherOptions = {
        ...DEFAULT_FILE_WATCHER_OPTIONS,
        ...options,
    };
    const pending = new Map();
    const flushPath = (filePath, eventType) => {
        const existing = pending.get(filePath);
        if (existing) {
            clearTimeout(existing);
        }
        pending.set(filePath, setTimeout(() => {
            pending.delete(filePath);
            if (!isIndexablePath(filePath)) {
                return;
            }
            // Emit audit event for file read
            getAuditService().emit({
                method: 'READ',
                path: filePath,
                resourceType: 'file',
                fileAction: 'read',
            });
            void readFile(filePath)
                .then((content) => indexer.processFileChange(filePath, content))
                .then((indexed) => onEvent?.({ eventType, filePath, indexed }))
                .catch(() => {
                onEvent?.({ eventType, filePath, indexed: false });
            });
        }, watcherOptions.debounceMs));
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
function estimateTokenCount(content) {
    return tokenize(content).length;
}
function tokenize(content) {
    return content
        .split(/\s+/)
        .map((x) => x.trim())
        .filter((x) => x.length > 0);
}
function hash(input) {
    return createHash("sha256").update(input).digest("hex");
}
//# sourceMappingURL=indexing.js.map