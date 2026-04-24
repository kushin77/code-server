import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
export class RepositoryIndexer {
    constructor(ollamaClient) {
        this.index = new Map();
        this.workspaceRoot = '';
        this.ollamaClient = ollamaClient;
    }
    async indexWorkspace() {
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
            }
            catch (error) {
                console.error(`Error indexing ${file}:`, error);
            }
        }
        console.log(`✅ Indexed ${this.index.size} files`);
    }
    async getRelevantContext(query) {
        if (this.index.size === 0) {
            return 'Repository context not yet indexed. Use "Ollama: Index Repository" command.';
        }
        try {
            const queryEmbedding = await this.ollamaClient.embed(query);
            const relevantDocs = this.findSimilar(queryEmbedding, 3);
            return relevantDocs
                .map((doc) => `File: ${doc.file}\n${doc.content}`)
                .join('\n\n---\n\n');
        }
        catch (error) {
            return 'Error retrieving context.';
        }
    }
    async findKeyFiles(rootPath) {
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
        const files = [];
        const maxFiles = 100; // Limit to top 100 files
        const walkDir = (dir, depth = 0) => {
            if (depth > 3 || files.length > maxFiles)
                return; // Limit depth
            try {
                const entries = fs.readdirSync(dir, { withFileTypes: true });
                for (const entry of entries) {
                    if (files.length >= maxFiles)
                        break;
                    // Skip common directories
                    if (['node_modules', '.git', 'dist', 'build', '.terraform', '__pycache__'].includes(entry.name)) {
                        continue;
                    }
                    const fullPath = path.join(dir, entry.name);
                    if (entry.isDirectory()) {
                        walkDir(fullPath, depth + 1);
                    }
                    else if (keyPatterns.some((pattern) => pattern.test(entry.name))) {
                        files.push(fullPath);
                    }
                }
            }
            catch (error) {
                // Ignore permission errors
            }
        };
        walkDir(rootPath);
        return files;
    }
    summarizeContent(content) {
        // Extract first 1000 chars as summary
        return content.substring(0, 1000).trim();
    }
    findSimilar(queryEmbedding, topK) {
        const similarities = [];
        for (const [file, doc] of this.index) {
            const similarity = this.cosineSimilarity(queryEmbedding, doc.embedding);
            similarities.push({ file, content: doc.content, similarity });
        }
        // Sort by similarity and return top K
        return similarities.sort((a, b) => b.similarity - a.similarity).slice(0, topK);
    }
    cosineSimilarity(a, b) {
        if (a.length === 0 || b.length === 0)
            return 0;
        let dotProduct = 0;
        let normA = 0;
        let normB = 0;
        for (let i = 0; i < Math.min(a.length, b.length); i++) {
            dotProduct += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }
        const denominator = Math.sqrt(normA) * Math.sqrt(normB);
        if (denominator === 0)
            return 0;
        return dotProduct / denominator;
    }
}
//# sourceMappingURL=repository-indexer.js.map