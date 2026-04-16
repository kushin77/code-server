import { describe, expect, it } from "vitest";
import {
  RepositoryIndexer,
  chunkByTokenWindow,
  inferLanguage,
  semanticBoundaries,
} from "../indexing";

describe("inferLanguage", () => {
  it("detects supported languages", () => {
    expect(inferLanguage("src/a.py")).toBe("python");
    expect(inferLanguage("src/a.ts")).toBe("typescript");
    expect(inferLanguage("src/a.go")).toBe("go");
    expect(inferLanguage("src/a.rs")).toBe("rust");
    expect(inferLanguage("src/A.java")).toBe("java");
    expect(inferLanguage("README.md")).toBe("unknown");
  });
});

describe("semanticBoundaries", () => {
  it("extracts python class/function boundaries", () => {
    const content = [
      "class User:",
      "  def __init__(self):",
      "    pass",
      "",
      "def helper():",
      "  return True",
    ].join("\n");

    const boundaries = semanticBoundaries(content, "python");
    expect(boundaries.length).toBeGreaterThanOrEqual(2);
    expect(boundaries[0].symbol).toBe("User");
  });

  it("falls back to single file boundary for unknown", () => {
    const boundaries = semanticBoundaries("hello world", "unknown");
    expect(boundaries).toHaveLength(1);
    expect(boundaries[0].symbol).toBe("file");
  });
});

describe("chunkByTokenWindow", () => {
  it("applies overlap window", () => {
    const content = "a b c d e f g h";
    const chunks = chunkByTokenWindow(content, 4, 1);
    expect(chunks).toHaveLength(3);
    expect(chunks[0]).toBe("a b c d");
    expect(chunks[1]).toBe("d e f g");
  });
});

describe("RepositoryIndexer", () => {
  it("indexes repository files into semantic chunks", async () => {
    const indexer = new RepositoryIndexer({ chunkSizeTokens: 12, chunkOverlapTokens: 2 });

    const result = await indexer.indexRepository([
      {
        path: "backend/src/foo.py",
        content: [
          "class Foo:",
          "  def run(self):",
          "    return 1",
          "",
          "def util(a, b):",
          "  return a + b",
        ].join("\n"),
      },
      {
        path: "backend/src/bar.ts",
        content: [
          "export function sum(a:number,b:number){",
          "  return a+b",
          "}",
        ].join("\n"),
      },
    ]);

    expect(result.indexedFiles).toBe(2);
    expect(result.indexedChunks).toBeGreaterThan(0);
    expect(indexer.getAllChunks().length).toBe(result.indexedChunks);
  });

  it("does not reindex unchanged file", async () => {
    const indexer = new RepositoryIndexer();
    const file = {
      path: "backend/src/sample.ts",
      content: "export function a(){ return 1 }",
    };

    await indexer.indexRepository([file]);
    const changed = await indexer.reindexChangedFile(file);
    expect(changed).toBe(false);
  });

  it("reindexes changed file and keeps queue depth stable", async () => {
    const indexer = new RepositoryIndexer();

    await indexer.indexRepository([
      { path: "backend/src/sample.ts", content: "export function a(){ return 1 }" },
    ]);

    const changed = await indexer.processFileChange(
      "backend/src/sample.ts",
      "export function a(){ return 2 }",
    );

    expect(changed).toBe(true);
    expect(indexer.getQueueDepth()).toBe(0);
  });

  it("deduplicates identical chunk content across files", async () => {
    const indexer = new RepositoryIndexer({ chunkSizeTokens: 20, chunkOverlapTokens: 0 });
    const content = "export function shared(){ return 42 }";

    await indexer.indexRepository([
      { path: "a.ts", content },
      { path: "b.ts", content },
    ]);

    expect(indexer.getAllChunks().length).toBe(1);
  });

  it("returns ranked keyword search results", async () => {
    const indexer = new RepositoryIndexer();

    await indexer.indexRepository([
      { path: "a.ts", content: "function auth login token validate session" },
      { path: "b.ts", content: "function math add subtract multiply divide" },
    ]);

    const results = indexer.search("auth token", 5);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].chunk.content).toContain("auth");
  });

  it("throws when queue is full", async () => {
    const indexer = new RepositoryIndexer({ maxQueueSize: 0 });

    await expect(
      indexer.reindexChangedFile({ path: "a.ts", content: "function x(){}" }),
    ).rejects.toThrow("Index queue is full");
  });
});
