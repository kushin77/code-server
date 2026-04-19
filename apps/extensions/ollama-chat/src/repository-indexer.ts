import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { OllamaClient } from './ollama-client';

export class RepositoryIndexer {
  private ollamaClient: OllamaClient;
  private index: Map<string, { content: string; embedding: number[] }> = new Map();
  private workspaceRoot: string = '';

  constructor(ollamaClient: OllamaClient) {
    this.ollamaClient = ollamaClient;
  }

  async indexWorkspace(): Promise<void> {
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders || workspaceFolders.length === 0) {
      throw new Error('No workspace folder found');
    }

    this.workspaceRoot = workspaceFolders[0].uri.fsPath;

    // Index key files: README, package.json, main source files
    const filesToIndex = await this.findKeyFiles(this.workspaceRoot);

    for (const file of filesToIndex) {
      try {
        const content = fs.readFileSync(file, 'utf-8');
        const summary = this.summarizeContent(content);
        const embedding = await this.ollamaClient.embed(summary);
        this.index.set(file, { content: summary, embedding });
      } catch (error) {
        console.error(`Error indexing ${file}:`, error);
      }
    }

    console.log(`✅ Indexed ${this.index.size} files`);
  }

  async getRelevantContext(query: string): Promise<string> {
    if (this.index.size === 0) {
      return 'Repository context not yet indexed. Use "Ollama: Index Repository" command.';
    }

    try {
      const queryEmbedding = await this.ollamaClient.embed(query);
      const relevantDocs = this.findSimilar(queryEmbedding, 3);

      return relevantDocs
        .map((doc) => `File: ${doc.file}\n${doc.content}`)
        .join('\n\n---\n\n');
    } catch (error) {
      return 'Error retrieving context.';
    }
  }

  private async findKeyFiles(rootPath: string): Promise<string[]> {
    const keyPatterns = [
      /README/i,
      /package\.json/,
      /\.ts$/,
      /\.js$/,
      /\.py$/,
      /\.go$/,
      /\.rs$/,
      /dockerfile/i,
      /makefile/i,
      /terraform/i,
    ];

    const files: string[] = [];
    const maxFiles = 100; // Limit to top 100 files

    const walkDir = (dir: string, depth: number = 0) => {
      if (depth > 3 || files.length > maxFiles) return; // Limit depth

      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
          if (files.length >= maxFiles) break;

          // Skip common directories
          if (['node_modules', '.git', 'dist', 'build', '.terraform', '__pycache__'].includes(entry.name)) {
            continue;
          }

          const fullPath = path.join(dir, entry.name);

          if (entry.isDirectory()) {
            walkDir(fullPath, depth + 1);
          } else if (keyPatterns.some((pattern) => pattern.test(entry.name))) {
            files.push(fullPath);
          }
        }
      } catch (error) {
        // Ignore permission errors
      }
    };

    walkDir(rootPath);
    return files;
  }

  private summarizeContent(content: string): string {
    // Extract first 1000 chars as summary
    return content.substring(0, 1000).trim();
  }

  private findSimilar(
    queryEmbedding: number[],
    topK: number
  ): Array<{ file: string; content: string; similarity: number }> {
    const similarities: Array<{ file: string; content: string; similarity: number }> = [];

    for (const [file, doc] of this.index) {
      const similarity = this.cosineSimilarity(queryEmbedding, doc.embedding);
      similarities.push({ file, content: doc.content, similarity });
    }

    // Sort by similarity and return top K
    return similarities.sort((a, b) => b.similarity - a.similarity).slice(0, topK);
  }

  private cosineSimilarity(a: number[], b: number[]): number {
    if (a.length === 0 || b.length === 0) return 0;

    let dotProduct = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < Math.min(a.length, b.length); i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    const denominator = Math.sqrt(normA) * Math.sqrt(normB);
    if (denominator === 0) return 0;

    return dotProduct / denominator;
  }
}
