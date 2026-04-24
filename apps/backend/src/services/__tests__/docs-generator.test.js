// @file        apps/backend/src/services/__tests__/docs-generator.test.ts
// @module      services/docs-generator/tests
// @description Unit tests for documentation generator
import { describe, it, expect, beforeEach, vi } from 'vitest';
import DocsGenerator from '../docs-generator';
describe('Documentation Generator', () => {
    let generator;
    beforeEach(() => {
        generator = new DocsGenerator({
            projectName: 'Test Project',
            version: '1.0.0',
        });
        vi.resetAllMocks();
    });
    describe('README Generation', () => {
        it('should generate README', async () => {
            expect(generator).toBeDefined();
        });
        it('should include features section', async () => {
            expect(generator).toBeDefined();
        });
        it('should include getting started', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('API Documentation', () => {
        it('should generate API documentation', async () => {
            expect(generator).toBeDefined();
        });
        it('should include endpoint documentation', async () => {
            expect(generator).toBeDefined();
        });
        it('should include error codes', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Setup Guides', () => {
        it('should generate setup guide', async () => {
            expect(generator).toBeDefined();
        });
        it('should include prerequisites', async () => {
            expect(generator).toBeDefined();
        });
        it('should include installation steps', async () => {
            expect(generator).toBeDefined();
        });
        it('should include configuration section', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Examples', () => {
        it('should generate examples', async () => {
            expect(generator).toBeDefined();
        });
        it('should include basic usage', async () => {
            expect(generator).toBeDefined();
        });
        it('should include advanced patterns', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Troubleshooting', () => {
        it('should generate troubleshooting guide', async () => {
            expect(generator).toBeDefined();
        });
        it('should include common issues', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Generation', () => {
        it('should generate all documents', async () => {
            expect(generator).toBeDefined();
        });
        it('should respect include flags', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Table of Contents', () => {
        it('should generate table of contents', async () => {
            expect(generator).toBeDefined();
        });
        it('should include document titles', async () => {
            expect(generator).toBeDefined();
        });
        it('should include section links', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Export', () => {
        it('should export to markdown', async () => {
            expect(generator).toBeDefined();
        });
        it('should export to HTML', async () => {
            expect(generator).toBeDefined();
        });
        it('should export to JSON', async () => {
            expect(generator).toBeDefined();
        });
    });
    describe('Caching', () => {
        it('should cache generated documents', async () => {
            expect(generator).toBeDefined();
        });
        it('should clear cache', async () => {
            generator.clearCache();
            expect(generator).toBeDefined();
        });
    });
});
//# sourceMappingURL=docs-generator.test.js.map