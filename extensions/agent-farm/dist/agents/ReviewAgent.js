"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReviewAgent = void 0;
const types_1 = require("../types");
class ReviewAgent extends types_1.Agent {
    constructor() {
        super(...arguments);
        this.name = 'ReviewAgent';
        this.domain = 'Code Quality & Best Practices';
    }
    async analyze(context) {
        this.log('Performing code review...');
        const recommendations = [];
        const content = context.content;
        // Code quality checks (expanded in full implementation)
        // Check for error handling
        if (!content.includes('try') && !content.includes('catch')) {
            recommendations.push('Consider adding error handling (try/catch blocks)');
        }
        // Check for comments
        const commentRegex = /(\/\/|\/\*|\*\/)/g;
        const comments = Array.from(content.matchAll(commentRegex));
        if (comments.length < content.split('\n').length * 0.1) {
            recommendations.push('Add more comments to explain complex logic');
        }
        // Check for unused variables (basic check)
        const varRegex = /(const|let|var)\s+(\w+)/g;
        const declaredVars = new Set();
        let match;
        while ((match = varRegex.exec(content)) !== null) {
            declaredVars.add(match[2]);
        }
        // Check for security issues
        if (content.includes('eval(')) {
            recommendations.push('Security: Remove eval() usage');
        }
        if (content.includes('innerHTML')) {
            recommendations.push('Security: Use textContent instead of innerHTML to prevent XSS');
        }
        // Check for console.log (should use proper logging)
        if (content.match(/console\.(log|warn|error)\(/g)) {
            recommendations.push('Use proper logging framework instead of console methods');
        }
        return this.formatOutput(`Code review complete. Found ${recommendations.length} quality improvements.`, recommendations, recommendations.length > 0 ? 'warning' : 'info');
    }
    async coordinate(context, previousResults) {
        this.log('Reviewing code quality issues from other agents...');
        // Implementation for multi-agent coordination
    }
}
exports.ReviewAgent = ReviewAgent;
//# sourceMappingURL=ReviewAgent.js.map