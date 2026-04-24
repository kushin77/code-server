// @file        apps/session-broker/src/terminal-output-dlp.ts
// @module      security/data-loss-prevention
// @description Terminal output Data Loss Prevention - detects and blocks credential/PII leakage in terminal
import { EventEmitter } from 'events';
const DEFAULT_DLP_CONFIG = {
    enabled: process.env.TERMINAL_DLP_ENABLED !== 'false',
    mode: process.env.TERMINAL_DLP_MODE || 'redact',
    blockCritical: process.env.TERMINAL_DLP_BLOCK_CRITICAL !== 'false',
    auditLog: process.env.TERMINAL_DLP_AUDIT_LOG !== 'false',
    metricsEnabled: process.env.TERMINAL_DLP_METRICS !== 'false',
};
/**
 * Terminal Output DLP Scanner
 * Protects against accidental credential leakage in terminal output
 */
export class TerminalOutputDLP extends EventEmitter {
    constructor(config = {}) {
        super();
        this.metrics = {
            scansTotal: 0,
            blockedTotal: 0,
            redactedTotal: 0,
            patternsMatched: new Map(),
        };
        this.config = { ...DEFAULT_DLP_CONFIG, ...config };
        this.patterns = this.initializePatterns();
    }
    initializePatterns() {
        return [
            // CRITICAL: Private Keys
            {
                regex: /-----BEGIN\s(?:RSA|OPENSSH|DSA|EC|PGP)\s(?:PRIVATE|ENCRYPTED)\sKEY.*?-----END/gis,
                name: 'private-key-block',
                category: 'credentials',
                severity: 'critical',
                action: 'block',
            },
            // CRITICAL: GitHub Tokens
            {
                regex: /(ghp_[A-Za-z0-9_]{36}|ghu_[A-Za-z0-9_]{36}|ghs_[A-Za-z0-9_]{36})/g,
                name: 'github-pat',
                category: 'credentials',
                severity: 'critical',
                action: 'block',
                replacement: '***GITHUB_PAT_REDACTED***',
            },
            // CRITICAL: Slack Tokens
            {
                regex: /(xox[baprs]-[0-9]{10,13}-[0-9]{10,13}[a-zA-Z0-9-]*)/g,
                name: 'slack-token',
                category: 'credentials',
                severity: 'critical',
                action: 'block',
                replacement: '***SLACK_TOKEN_REDACTED***',
            },
            // CRITICAL: Bearer Tokens
            {
                regex: /bearer\s+([A-Za-z0-9\-._~+/]+=*)/gi,
                name: 'bearer-token',
                category: 'credentials',
                severity: 'critical',
                action: 'block',
                replacement: 'Bearer ***REDACTED***',
            },
            // HIGH: AWS Credentials
            {
                regex: /(?:AKIA|ASIA)[0-9A-Z]{16}/g,
                name: 'aws-access-key',
                category: 'credentials',
                severity: 'high',
                action: 'redact',
                replacement: '***AWS_KEY_REDACTED***',
            },
            // HIGH: Database Passwords
            {
                regex: /(?:postgres|mysql|mariadb|mongodb|redis)[_-]?(?:password|passwd|pwd)\s*[:=]\s*(?:['"])?([^\s'"]+)(?:['"])?/gi,
                name: 'db-password',
                category: 'credentials',
                severity: 'high',
                action: 'redact',
                replacement: 'password=***REDACTED***',
            },
            // HIGH: API Keys
            {
                regex: /(?:api[_-]?key|apikey|api_secret|secret)\s*[:=]\s*(?:['"])?([A-Za-z0-9\-_]{32,})(?:['"])?/gi,
                name: 'api-key',
                category: 'credentials',
                severity: 'high',
                action: 'redact',
                replacement: 'api_key=***REDACTED***',
            },
            // MEDIUM: Email Addresses
            {
                regex: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g,
                name: 'email-address',
                category: 'pii',
                severity: 'medium',
                action: 'redact',
                replacement: '***EMAIL_REDACTED***',
            },
            // MEDIUM: IP Addresses
            {
                regex: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/g,
                name: 'ip-address',
                category: 'pii',
                severity: 'medium',
                action: 'redact',
                replacement: '***IP_REDACTED***',
            },
        ];
    }
    /**
     * Scan terminal line for sensitive patterns
     */
    scan(content) {
        if (!this.config.enabled) {
            return {
                action: 'allowed',
                sanitized: content,
                matches: [],
                blockedCount: 0,
                redactedCount: 0,
                severity: 'low',
            };
        }
        let sanitized = content;
        const matches = [];
        let blockedCount = 0;
        let redactedCount = 0;
        let maxSeverity = 'low';
        for (const pattern of this.patterns) {
            let match;
            const regex = new RegExp(pattern.regex.source, pattern.regex.flags);
            while ((match = regex.exec(content)) !== null) {
                const position = this.getPosition(content, match.index);
                const matchedText = match[0];
                matches.push({
                    pattern: pattern.name,
                    matched: matchedText.substring(0, 50),
                    severity: pattern.severity,
                    category: pattern.category,
                    position,
                });
                this.metrics.patternsMatched.set(pattern.name, (this.metrics.patternsMatched.get(pattern.name) || 0) + 1);
                if (this.severityRank(pattern.severity) > this.severityRank(maxSeverity)) {
                    maxSeverity = pattern.severity;
                }
                if (this.config.blockCritical && pattern.severity === 'critical') {
                    blockedCount++;
                }
                else if (this.config.mode === 'block' && pattern.action === 'block') {
                    blockedCount++;
                }
                else {
                    const replacement = pattern.replacement || `***${pattern.name.toUpperCase()}***`;
                    sanitized = sanitized.replace(matchedText, replacement);
                    redactedCount++;
                }
            }
        }
        this.metrics.scansTotal++;
        this.metrics.blockedTotal += blockedCount;
        this.metrics.redactedTotal += redactedCount;
        let action = 'allowed';
        if (blockedCount > 0) {
            action = 'blocked';
        }
        else if (redactedCount > 0) {
            action = 'redacted';
        }
        if (matches.length > 0) {
            this.emit('dlp-detection', {
                action,
                matchCount: matches.length,
                severity: maxSeverity,
            });
            if (this.config.auditLog) {
                this.auditLog(action, matches);
            }
        }
        return {
            action,
            sanitized: action === 'blocked' ? '' : sanitized,
            matches,
            blockedCount,
            redactedCount,
            severity: maxSeverity,
        };
    }
    /**
     * Validate binary data
     */
    validateBinary(buffer, maxSize = 10 * 1024 * 1024) {
        if (!this.config.enabled)
            return true;
        if (buffer.length > maxSize) {
            throw new Error('Binary data exceeds max size for DLP validation');
        }
        const content = buffer.toString('utf-8', 0, Math.min(buffer.length, 100000));
        const result = this.scan(content);
        if (result.action === 'blocked') {
            throw new Error(`DLP: Binary data contains blocked patterns (${result.severity})`);
        }
        return true;
    }
    getPosition(content, index) {
        const lines = content.substring(0, index).split('\n');
        return {
            line: lines.length,
            column: lines[lines.length - 1].length,
        };
    }
    severityRank(severity) {
        const ranks = { critical: 4, high: 3, medium: 2, low: 1 };
        return ranks[severity] || 0;
    }
    auditLog(action, matches) {
        const timestamp = new Date().toISOString();
        const sessionId = process.env.SESSION_ID || 'unknown';
        const event = {
            timestamp,
            sessionId,
            action,
            matchCount: matches.length,
            patterns: matches.map((m) => m.pattern),
        };
        this.emit('audit-log', event);
    }
    getMetrics() {
        return {
            ...this.metrics,
            patternsMatched: Object.fromEntries(this.metrics.patternsMatched),
        };
    }
    resetMetrics() {
        this.metrics.scansTotal = 0;
        this.metrics.blockedTotal = 0;
        this.metrics.redactedTotal = 0;
        this.metrics.patternsMatched.clear();
    }
    addPattern(pattern) {
        this.patterns.push(pattern);
    }
    setEnabled(enabled) {
        this.config.enabled = enabled;
    }
    setMode(mode) {
        this.config.mode = mode;
    }
}
let globalDLP = null;
export function getTerminalDLP(config) {
    if (!globalDLP) {
        globalDLP = new TerminalOutputDLP(config);
    }
    return globalDLP;
}
export function resetTerminalDLP() {
    globalDLP = null;
}
//# sourceMappingURL=terminal-output-dlp.js.map