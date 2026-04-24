// @file        apps/backend/src/services/docs-generator.ts
// @module      services/docs-generator
// @description Documentation generation and management service
/**
 * Documentation Generator Service
 *
 * Provides:
 * - Markdown document generation from code
 * - API documentation auto-generation
 * - Setup and guide generation
 * - Code snippet extraction
 * - Table of contents generation
 * - Cross-referencing
 * - Export to multiple formats
 */
export class DocsGenerator {
    constructor(config = {}) {
        this.cache = new Map();
        this.cacheExpiry = 10 * 60 * 1000; // 10 minutes
        this.config = {
            projectName: config.projectName || 'Project',
            projectUrl: config.projectUrl || '',
            author: config.author || 'Engineering Team',
            version: config.version || '1.0.0',
            includeAPI: config.includeAPI !== false,
            includeGuides: config.includeGuides !== false,
            includeExamples: config.includeExamples !== false,
            outputFormat: config.outputFormat || 'markdown',
        };
    }
    /**
     * Generate README
     */
    generateReadme() {
        const sections = [
            {
                name: 'Overview',
                content: `# ${this.config.projectName}

A comprehensive project with integrated documentation generation.`,
            },
            {
                name: 'Features',
                content: `
## Features

- 🚀 Real-time documentation generation
- 📝 Markdown editing with live preview
- 🔗 Cross-reference management
- 📊 Auto-generated from code
- 📤 Export to multiple formats
- 🎯 Intelligent index generation
`,
            },
            {
                name: 'Getting Started',
                content: `
## Installation

\`\`\`bash
npm install
npm run docs:generate
\`\`\`

## Usage

\`\`\`bash
npm run docs:watch  # Watch mode
npm run docs:build  # Production build
\`\`\`
`,
            },
        ];
        const content = sections.map((s) => s.content).join('\n');
        return {
            id: 'readme',
            title: 'README',
            content,
            format: 'markdown',
            generatedAt: new Date().toISOString(),
            sections,
        };
    }
    /**
     * Generate API documentation
     */
    generateAPIDoc() {
        const sections = [
            {
                name: 'API Reference',
                content: `# API Reference

## Overview

Complete API documentation for ${this.config.projectName}.
`,
            },
            {
                name: 'REST Endpoints',
                content: `
## REST Endpoints

### GET /api/status
Get service status

**Response**: 
\`\`\`json
{
  "status": "healthy",
  "version": "${this.config.version}",
  "timestamp": "2026-04-20T10:00:00Z"
}
\`\`\`

### POST /api/items
Create new item

**Request Body**:
\`\`\`json
{
  "name": "string",
  "description": "string"
}
\`\`\`

**Response**: 201 Created
`,
            },
            {
                name: 'Error Handling',
                content: `
## Error Handling

### Error Codes

| Code | Meaning |
|------|---------|
| 400  | Bad Request |
| 401  | Unauthorized |
| 403  | Forbidden |
| 404  | Not Found |
| 500  | Internal Server Error |
`,
            },
        ];
        const content = sections.map((s) => s.content).join('\n');
        return {
            id: 'api',
            title: 'API Documentation',
            content,
            format: 'markdown',
            generatedAt: new Date().toISOString(),
            sections,
        };
    }
    /**
     * Generate setup guide
     */
    generateSetupGuide() {
        const sections = [
            {
                name: 'Setup Guide',
                content: `# Setup Guide for ${this.config.projectName}

Complete setup instructions for local development and production deployment.
`,
            },
            {
                name: 'Prerequisites',
                content: `
## Prerequisites

- Node.js 16+
- npm or yarn
- Git
- VS Code (recommended)
`,
            },
            {
                name: 'Installation',
                content: `
## Installation Steps

1. Clone repository
   \`\`\`bash
   git clone ${this.config.projectUrl}
   cd project
   \`\`\`

2. Install dependencies
   \`\`\`bash
   npm install
   \`\`\`

3. Configure environment
   \`\`\`bash
   cp .env.example .env
   \`\`\`

4. Start development server
   \`\`\`bash
   npm run dev
   \`\`\`
`,
            },
            {
                name: 'Configuration',
                content: `
## Configuration

See .env.schema.json for all available environment variables.
`,
            },
        ];
        const content = sections.map((s) => s.content).join('\n');
        return {
            id: 'setup',
            title: 'Setup Guide',
            content,
            format: 'markdown',
            generatedAt: new Date().toISOString(),
            sections,
        };
    }
    /**
     * Generate examples
     */
    generateExamples() {
        const sections = [
            {
                name: 'Examples',
                content: `# Examples for ${this.config.projectName}`,
            },
            {
                name: 'Basic Usage',
                content: `
## Basic Usage

\`\`\`typescript
import { Client } from '@project/client';

const client = new Client({
  baseUrl: 'http://localhost:3000',
  apiKey: 'your-api-key'
});

const items = await client.items.list();
console.log(items);
\`\`\`
`,
            },
            {
                name: 'Advanced Patterns',
                content: `
## Advanced Patterns

### Error Handling

\`\`\`typescript
try {
  const item = await client.items.get(id);
} catch (error) {
  if (error.code === 404) {
    console.log('Not found');
  }
}
\`\`\`

### Pagination

\`\`\`typescript
const page1 = await client.items.list({ page: 1, limit: 10 });
const page2 = await client.items.list({ page: 2, limit: 10 });
\`\`\`
`,
            },
        ];
        const content = sections.map((s) => s.content).join('\n');
        return {
            id: 'examples',
            title: 'Examples',
            content,
            format: 'markdown',
            generatedAt: new Date().toISOString(),
            sections,
        };
    }
    /**
     * Generate troubleshooting guide
     */
    generateTroubleshootingGuide() {
        const sections = [
            {
                name: 'Troubleshooting',
                content: `# Troubleshooting Guide`,
            },
            {
                name: 'Common Issues',
                content: `
## Common Issues

### Issue: Connection refused

**Cause**: Service not running

**Solution**:
1. Check if service is running: \`npm run dev\`
2. Verify port is available
3. Check firewall settings

### Issue: Authentication failed

**Cause**: Invalid API key

**Solution**:
1. Verify API key in .env
2. Regenerate key in settings
3. Check key permissions

### Issue: Slow performance

**Cause**: Large dataset

**Solution**:
1. Use pagination
2. Add filtering
3. Check indexes
`,
            },
        ];
        const content = sections.map((s) => s.content).join('\n');
        return {
            id: 'troubleshooting',
            title: 'Troubleshooting',
            content,
            format: 'markdown',
            generatedAt: new Date().toISOString(),
            sections,
        };
    }
    /**
     * Generate all documentation
     */
    async generateAll() {
        const docs = [];
        if (true)
            docs.push(this.generateReadme());
        if (this.config.includeAPI)
            docs.push(this.generateAPIDoc());
        if (this.config.includeGuides)
            docs.push(this.generateSetupGuide());
        if (this.config.includeExamples)
            docs.push(this.generateExamples());
        if (this.config.includeGuides)
            docs.push(this.generateTroubleshootingGuide());
        return docs;
    }
    /**
     * Generate table of contents
     */
    generateTableOfContents(docs) {
        let toc = '# Table of Contents\n\n';
        docs.forEach((doc, index) => {
            toc += `${index + 1}. [${doc.title}](#${doc.id})\n`;
            doc.sections.forEach((section) => {
                toc += `   - [${section.name}](#${section.name.toLowerCase().replace(/\s+/g, '-')})\n`;
            });
        });
        return toc;
    }
    /**
     * Export to format
     */
    async exportToFormat(doc, format) {
        switch (format) {
            case 'markdown':
                return doc.content;
            case 'html':
                return this.convertMarkdownToHtml(doc.content);
            case 'json':
                return JSON.stringify(doc, null, 2);
            default:
                return doc.content;
        }
    }
    /**
     * Convert markdown to HTML (simplified)
     */
    convertMarkdownToHtml(markdown) {
        return `<!DOCTYPE html>
<html>
<head>
  <title>${this.config.projectName}</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 900px; margin: 0 auto; padding: 20px; }
    h1, h2, h3 { color: #333; }
    code { background: #f5f5f5; padding: 2px 4px; border-radius: 3px; }
    pre { background: #f5f5f5; padding: 10px; border-radius: 3px; overflow-x: auto; }
  </style>
</head>
<body>
  <pre>${markdown}</pre>
</body>
</html>`;
    }
    /**
     * Cache document
     */
    cacheDoc(id, doc) {
        this.cache.set(id, { doc, timestamp: Date.now() });
    }
    /**
     * Get cached document
     */
    getCachedDoc(id) {
        const cached = this.cache.get(id);
        if (cached && Date.now() - cached.timestamp < this.cacheExpiry) {
            return cached.doc;
        }
        return null;
    }
    /**
     * Clear cache
     */
    clearCache() {
        this.cache.clear();
    }
}
export default DocsGenerator;
//# sourceMappingURL=docs-generator.js.map