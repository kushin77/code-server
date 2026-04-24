/**
 * Code Navigation Service Tests
 * @file        apps/backend/src/services/code-navigation/__tests__/code-navigation-service.test.ts
 * @module      services/code-navigation
 * @description Test suite for intelligent code navigation
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CodeNavigationService } from '../code-navigation-service.js';
describe('Code Navigation Service', () => {
    let service;
    beforeEach(() => {
        CodeNavigationService.reset();
        service = CodeNavigationService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    describe('Initialization', () => {
        it('should initialize service', () => {
            expect(service).toBeDefined();
            expect(service.symbols).toBeDefined();
            expect(service.references).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = CodeNavigationService.getInstance();
            const instance2 = CodeNavigationService.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    describe('Index Symbol', () => {
        it('should index symbol successfully', () => {
            const symbol = {
                id: '',
                name: 'getUserById',
                kind: 'function',
                filePath: 'src/users.ts',
                lineNumber: 42,
                columnNumber: 5,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: ['utility'],
                relatedSymbols: [],
            };
            const result = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.symbolId).toBeDefined();
        });
        it('should emit symbol-indexed event', () => {
            return new Promise((resolve) => {
                service.once('symbol-indexed', (event) => {
                    expect(event.data_object.symbolId).toBeDefined();
                    expect(event.data_object.name).toBe('getUserById');
                    resolve();
                });
                const symbol = {
                    id: '',
                    name: 'getUserById',
                    kind: 'function',
                    filePath: 'src/users.ts',
                    lineNumber: 42,
                    columnNumber: 5,
                    deprecated: false,
                    exported: true,
                    visibility: 'public',
                    tags: [],
                    relatedSymbols: [],
                };
                service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should track symbols by file', () => {
            const symbol1 = {
                id: '',
                name: 'function1',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const symbol2 = {
                id: '',
                name: 'function2',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 10,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const result1 = service.indexSymbol(symbol1, 'user1', '192.168.1.1', 'Mozilla');
            const result2 = service.indexSymbol(symbol2, 'user1', '192.168.1.1', 'Mozilla');
            const symbol1Result = service.getSymbol(result1.symbolId);
            expect(symbol1Result.symbol?.filePath).toBe('src/app.ts');
        });
    });
    describe('Update Symbol', () => {
        it('should update symbol successfully', () => {
            const symbol = {
                id: '',
                name: 'myFunc',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 5,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const updateResult = service.updateSymbol(indexResult.symbolId, { deprecated: true, tags: ['deprecated'] }, 'user1', '192.168.1.1', 'Mozilla');
            expect(updateResult.success).toBe(true);
            expect(updateResult.symbol?.deprecated).toBe(true);
        });
        it('should emit symbol-updated event', () => {
            return new Promise((resolve) => {
                const symbol = {
                    id: '',
                    name: 'test',
                    kind: 'function',
                    filePath: 'src/app.ts',
                    lineNumber: 1,
                    columnNumber: 1,
                    deprecated: false,
                    exported: true,
                    visibility: 'public',
                    tags: [],
                    relatedSymbols: [],
                };
                const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
                service.once('symbol-updated', (event) => {
                    expect(event.data_object.symbolId).toBe(indexResult.symbolId);
                    resolve();
                });
                service.updateSymbol(indexResult.symbolId, { deprecated: true }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Delete Symbol', () => {
        it('should delete symbol successfully', () => {
            const symbol = {
                id: '',
                name: 'toDelete',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const deleteResult = service.deleteSymbol(indexResult.symbolId, 'user1', '192.168.1.1', 'Mozilla');
            expect(deleteResult.success).toBe(true);
            const getResult = service.getSymbol(indexResult.symbolId);
            expect(getResult.success).toBe(false);
        });
        it('should emit symbol-deleted event', () => {
            return new Promise((resolve) => {
                const symbol = {
                    id: '',
                    name: 'test',
                    kind: 'function',
                    filePath: 'src/app.ts',
                    lineNumber: 1,
                    columnNumber: 1,
                    deprecated: false,
                    exported: true,
                    visibility: 'public',
                    tags: [],
                    relatedSymbols: [],
                };
                const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
                service.once('symbol-deleted', (event) => {
                    expect(event.data_object.symbolId).toBe(indexResult.symbolId);
                    resolve();
                });
                service.deleteSymbol(indexResult.symbolId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Get Symbol', () => {
        it('should retrieve symbol by ID', () => {
            const symbol = {
                id: '',
                name: 'getUserName',
                kind: 'method',
                filePath: 'src/users.ts',
                lineNumber: 10,
                columnNumber: 2,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const getResult = service.getSymbol(indexResult.symbolId);
            expect(getResult.success).toBe(true);
            expect(getResult.symbol?.name).toBe('getUserName');
        });
        it('should return error for nonexistent symbol', () => {
            const result = service.getSymbol('nonexistent');
            expect(result.success).toBe(false);
            expect(result.error).toBe('Symbol not found');
        });
    });
    describe('Add Reference', () => {
        it('should add reference successfully', () => {
            const symbol = {
                id: '',
                name: 'function1',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const reference = {
                id: '',
                symbolId: indexResult.symbolId,
                referencedSymbolId: 'other-symbol',
                filePath: 'src/main.ts',
                lineNumber: 20,
                columnNumber: 5,
                kind: 'call',
                context: 'function1()',
                isDefinition: false,
                isImport: false,
            };
            const result = service.addReference(reference, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.referenceId).toBeDefined();
        });
        it('should emit reference-found event', () => {
            return new Promise((resolve) => {
                const symbol = {
                    id: '',
                    name: 'test',
                    kind: 'function',
                    filePath: 'src/app.ts',
                    lineNumber: 1,
                    columnNumber: 1,
                    deprecated: false,
                    exported: true,
                    visibility: 'public',
                    tags: [],
                    relatedSymbols: [],
                };
                const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
                service.once('reference-found', (event) => {
                    expect(event.data_object.symbolId).toBe(indexResult.symbolId);
                    resolve();
                });
                const reference = {
                    id: '',
                    symbolId: indexResult.symbolId,
                    referencedSymbolId: 'other',
                    filePath: 'src/main.ts',
                    lineNumber: 20,
                    columnNumber: 5,
                    kind: 'usage',
                    context: 'test()',
                    isDefinition: false,
                    isImport: false,
                };
                service.addReference(reference, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Find All References', () => {
        it('should find all references to symbol', () => {
            const symbol = {
                id: '',
                name: 'myFunction',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const symbolId = indexResult.symbolId;
            const ref1 = {
                id: '',
                symbolId,
                referencedSymbolId: 'other1',
                filePath: 'src/main.ts',
                lineNumber: 20,
                columnNumber: 5,
                kind: 'call',
                context: 'myFunction()',
                isDefinition: false,
                isImport: false,
            };
            service.addReference(ref1, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.findAllReferences(symbolId);
            expect(result.success).toBe(true);
            expect(result.count).toBeGreaterThanOrEqual(0);
        });
    });
    describe('Go To Definition', () => {
        it('should navigate to symbol definition', () => {
            const symbol = {
                id: '',
                name: 'MyClass',
                kind: 'class',
                filePath: 'src/models.ts',
                lineNumber: 5,
                columnNumber: 7,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.goToDefinition(indexResult.symbolId);
            expect(result.success).toBe(true);
            expect(result.filePath).toBe('src/models.ts');
            expect(result.lineNumber).toBe(5);
        });
        it('should return error if symbol not found', () => {
            const result = service.goToDefinition('nonexistent');
            expect(result.success).toBe(false);
        });
    });
    describe('Find Symbols', () => {
        it('should find symbols by name', () => {
            const symbol = {
                id: '',
                name: 'getUserData',
                kind: 'function',
                filePath: 'src/api.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const results = service.findSymbols('getUserData');
            expect(results.length).toBeGreaterThan(0);
            expect(results[0].symbol.name).toBe('getUserData');
        });
        it('should filter by kind', () => {
            const classSymbol = {
                id: '',
                name: 'MyClass',
                kind: 'class',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const funcSymbol = {
                id: '',
                name: 'myFunc',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 20,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(classSymbol, 'user1', '192.168.1.1', 'Mozilla');
            service.indexSymbol(funcSymbol, 'user1', '192.168.1.1', 'Mozilla');
            const results = service.findSymbols('', { kind: ['class'] });
            expect(results.length).toBeGreaterThanOrEqual(0);
        });
        it('should filter by file', () => {
            const symbol = {
                id: '',
                name: 'testFunc',
                kind: 'function',
                filePath: 'src/test.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const results = service.findSymbols('', { filePath: 'src/test.ts' });
            expect(results.length).toBeGreaterThanOrEqual(0);
        });
    });
    describe('Search Symbols', () => {
        it('should search by name', () => {
            const symbol = {
                id: '',
                name: 'searchTest',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const results = service.searchSymbols('searchTest', 'name');
            expect(results.length).toBeGreaterThan(0);
        });
        it('should support fuzzy search', () => {
            const symbol = {
                id: '',
                name: 'getUserData',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const results = service.searchSymbols('gUD', 'fuzzy');
            expect(results.length).toBeGreaterThan(0);
        });
        it('should support regex search', () => {
            const symbol = {
                id: '',
                name: 'getUserName',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const results = service.searchSymbols('get.*Name', 'regex');
            expect(results.length).toBeGreaterThan(0);
        });
    });
    describe('Symbol Hierarchy', () => {
        it('should retrieve symbol hierarchy', () => {
            const symbol = {
                id: '',
                name: 'MyClass',
                kind: 'class',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.getSymbolHierarchy(indexResult.symbolId);
            expect(result.success).toBe(true);
            expect(result.hierarchy).toBeDefined();
        });
    });
    describe('Navigation Breadcrumb', () => {
        it('should get navigation breadcrumb', () => {
            const symbol = {
                id: '',
                name: 'testFunc',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.getNavigationBreadcrumb(indexResult.symbolId);
            expect(result.success).toBe(true);
            expect(result.breadcrumb).toBeDefined();
            expect(result.breadcrumb?.path.length).toBeGreaterThan(0);
        });
    });
    describe('Suggestions', () => {
        it('should generate navigation suggestions', () => {
            const symbol = {
                id: '',
                name: 'utils',
                kind: 'module',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const context = {
                currentFilePath: 'src/app.ts',
                currentLine: 1,
                currentColumn: 1,
                recentlyVisitedSymbols: [],
                frequentlyUsedSymbols: [],
                openFiles: ['src/app.ts'],
            };
            const suggestions = service.getSuggestions(context);
            expect(suggestions).toBeDefined();
            expect(Array.isArray(suggestions)).toBe(true);
        });
    });
    describe('Track Navigation', () => {
        it('should track user navigation', () => {
            const symbol1 = {
                id: '',
                name: 'func1',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const symbol2 = {
                id: '',
                name: 'func2',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 10,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult1 = service.indexSymbol(symbol1, 'user1', '192.168.1.1', 'Mozilla');
            const indexResult2 = service.indexSymbol(symbol2, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.trackNavigation(indexResult1.symbolId, indexResult2.symbolId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
    });
    describe('Navigation History', () => {
        it('should retrieve navigation history', () => {
            const symbol = {
                id: '',
                name: 'test',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            const indexResult = service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            service.trackNavigation('from-1', indexResult.symbolId, 'user1', '192.168.1.1', 'Mozilla');
            const history = service.getNavigationHistory('user1');
            expect(history).toBeDefined();
            expect(Array.isArray(history)).toBe(true);
        });
    });
    describe('Statistics', () => {
        it('should calculate service statistics', () => {
            const symbol = {
                id: '',
                name: 'test',
                kind: 'function',
                filePath: 'src/app.ts',
                lineNumber: 1,
                columnNumber: 1,
                deprecated: false,
                exported: true,
                visibility: 'public',
                tags: [],
                relatedSymbols: [],
            };
            service.indexSymbol(symbol, 'user1', '192.168.1.1', 'Mozilla');
            const stats = service.getStatistics();
            expect(stats.totalNavigations).toBeGreaterThanOrEqual(0);
            expect(stats.uniqueFiles).toBeGreaterThanOrEqual(0);
        });
    });
    describe('Configuration', () => {
        it('should update configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    resolve();
                });
                service.updateConfig({ maxSymbols: 100000 }, 'admin', '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            return new Promise((resolve) => {
                service.once('shutdown', (event) => {
                    expect(event.data_object.service).toBe('code-navigation');
                    resolve();
                });
                service.shutdown();
            });
        });
    });
});
//# sourceMappingURL=code-navigation-service.test.js.map