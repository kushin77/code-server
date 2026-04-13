"use strict";
/**
 * Phase 4B: Advanced ML Semantic Search
 * QueryUnderstanding - Parse and expand natural language queries into code patterns
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.QueryUnderstanding = void 0;
class QueryUnderstanding {
    constructor() {
        this.intentKeywords = {
            search: ['find', 'search', 'locate', 'where', 'look'],
            find: ['find', 'get', 'fetch', 'retrieve', 'lookup'],
            analyze: ['analyze', 'check', 'review', 'scan', 'examine'],
            optimize: ['optimize', 'improve', 'speed up', 'fast', 'performance'],
            refactor: ['refactor', 'clean', 'rewrite', 'restructure', 'improve'],
            debug: ['debug', 'fix', 'error', 'crash', 'issue', 'bug'],
            test: ['test', 'coverage', 'testcase', 'unittest', 'verify'],
        };
        this.synonymMap = new Map([
            ['function', ['method', 'procedure', 'routine', 'handler', 'callback']],
            ['class', ['type', 'interface', 'struct', 'model', 'entity']],
            ['variable', ['constant', 'property', 'field', 'attribute', 'parameter']],
            ['error', ['exception', 'failure', 'bug', 'crash', 'problem']],
            ['database', ['db', 'storage', 'cache', 'sql', 'query']],
            ['api', ['endpoint', 'service', 'route', 'handler', 'controller']],
            ['performance', ['speed', 'optimization', 'latency', 'throughput', 'efficiency']],
        ]);
        this.codePatterns = {
            'async': /async\s+(function|\w+\s*=>|[\w.]+\s*\()/,
            'promise': /Promise<|\.then\(|\.catch\(|await /,
            'error-handling': /try\s*{|catch\s*\(|throw |Error/,
            'loop': /for\s*\(|while\s*\(|forEach|map\(|reduce\(/,
            'database': /query|insert|update|delete|select|from|where/i,
            'http': /GET|POST|PUT|DELETE|fetch|axios|http\./i,
            'security': /encrypt|decrypt|hash|token|auth|password|secret/i,
            'performance': /cache|optimize|lazy|defer|async|parallel/i,
        };
    }
    /**
     * Understand a natural language query
     */
    understandQuery(query) {
        const lowercaseQuery = query.toLowerCase();
        // Detect intent
        let intent = 'search';
        for (const [key, keywords] of Object.entries(this.intentKeywords)) {
            if (keywords.some((kw) => lowercaseQuery.includes(kw))) {
                intent = key;
                break;
            }
        }
        // Extract entities (programming concepts)
        const entities = this.extractEntities(query);
        // Extract constraints
        const constraints = this.extractConstraints(query);
        // Extract keywords
        const keywords = this.extractKeywords(query);
        return {
            type: intent,
            keywords,
            entities,
            constraints,
        };
    }
    /**
     * Expand query with synonyms and related terms
     */
    expandQuery(query) {
        const intent = this.understandQuery(query);
        const synonyms = this.findSynonyms(query);
        const patterns = this.findCodePatterns(query);
        const expandedTerms = this.generateExpandedTerms(query, intent);
        return {
            original: query,
            intent,
            synonyms,
            patterns,
            expandedTerms,
        };
    }
    /**
     * Extract programming entities (classes, functions, variables, etc.)
     */
    extractEntities(query) {
        const entities = [];
        // Look for programming keywords/entities
        const programmingTerms = [
            'function', 'class', 'interface', 'type', 'variable',
            'constant', 'method', 'property', 'parameter', 'argument',
            'loop', 'condition', 'array', 'object', 'string', 'number',
            'error', 'exception', 'promise', 'async', 'await', 'yield',
            'generator', 'iterator', 'module', 'library', 'package',
        ];
        for (const term of programmingTerms) {
            if (query.toLowerCase().includes(term)) {
                entities.push(term);
            }
        }
        return entities;
    }
    /**
     * Extract constraints from query (language, complexity, etc.)
     */
    extractConstraints(query) {
        const constraints = [];
        // Language constraints
        const languages = ['typescript', 'javascript', 'python', 'java', 'golang', 'rust'];
        for (const lang of languages) {
            if (query.toLowerCase().includes(lang)) {
                constraints.push({
                    type: 'language',
                    operator: '==',
                    value: lang,
                });
            }
        }
        // Complexity constraints
        if (query.toLowerCase().includes('simple')) {
            constraints.push({
                type: 'complexity',
                operator: '<',
                value: 50,
            });
        }
        else if (query.toLowerCase().includes('complex')) {
            constraints.push({
                type: 'complexity',
                operator: '>',
                value: 100,
            });
        }
        // Test coverage constraints
        if (query.toLowerCase().includes('untested')) {
            constraints.push({
                type: 'testCoverage',
                operator: '==',
                value: 0,
            });
        }
        else if (query.toLowerCase().includes('well-tested') || query.toLowerCase().includes('covered')) {
            constraints.push({
                type: 'testCoverage',
                operator: '>',
                value: 80,
            });
        }
        return constraints;
    }
    /**
     * Extract main keywords from query
     */
    extractKeywords(query) {
        // Remove stop words and extract main terms
        const stopWords = ['the', 'a', 'an', 'and', 'or', 'in', 'on', 'at', 'to', 'for', 'of'];
        const words = query.split(/\s+/);
        return words
            .filter((word) => !stopWords.includes(word.toLowerCase()) && word.length > 3)
            .map((w) => w.toLowerCase());
    }
    /**
     * Find synonyms for query terms
     */
    findSynonyms(query) {
        const synonyms = [];
        for (const [term, synList] of this.synonymMap) {
            if (query.toLowerCase().includes(term)) {
                synonyms.push(...synList);
            }
        }
        return [...new Set(synonyms)]; // Remove duplicates
    }
    /**
     * Find relevant code patterns
     */
    findCodePatterns(query) {
        const patterns = [];
        const lowercaseQuery = query.toLowerCase();
        for (const [pattern, regex] of Object.entries(this.codePatterns)) {
            if (lowercaseQuery.includes(pattern)) {
                patterns.push(pattern);
            }
        }
        return patterns;
    }
    /**
     * Generate expanded terms for better matching
     */
    generateExpandedTerms(query, intent) {
        const expanded = new Set();
        // Add intent-related terms
        expanded.add(intent.type);
        // Add extracted keywords
        intent.keywords.forEach((kw) => expanded.add(kw));
        // Add synonyms
        for (const [original, synList] of this.synonymMap) {
            if (intent.keywords.some((kw) => kw.includes(original))) {
                synList.forEach((syn) => expanded.add(syn));
            }
        }
        // Add pattern-related terms
        const patternTerms = {
            'async': ['promise', 'await', 'callback', 'concurrent'],
            'promise': ['async', 'await', 'then', 'resolve', 'reject'],
            'error-handling': ['exception', 'catch', 'try', 'throw'],
            'loop': ['iteration', 'traverse', 'iterate', 'foreach'],
            'database': ['query', 'sql', 'orm', 'persistence', 'store'],
            'http': ['request', 'response', 'rest', 'api', 'network'],
            'security': ['authentication', 'authorization', 'encryption', 'validation'],
            'performance': ['optimization', 'efficiency', 'cache', 'memoization'],
        };
        for (const [pattern, terms] of Object.entries(patternTerms)) {
            if (intent.keywords.some((kw) => kw.includes(pattern))) {
                terms.forEach((t) => expanded.add(t));
            }
        }
        return Array.from(expanded);
    }
}
exports.QueryUnderstanding = QueryUnderstanding;
//# sourceMappingURL=QueryUnderstanding.js.map