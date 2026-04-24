export class TerminalDLPScanner {
    constructor() {
        // Compile regex patterns for performance
        this.patterns = new Map([
            ['github_pat', /ghp_[A-Za-z0-9_]{36}/g],
            ['slack_token', /xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+/g],
            ['bearer_token', /Bearer [A-Za-z0-9\-._~+/]+=+/g],
            ['aws_access_key', /AKIA[0-9A-Z]{16}/g],
            ['aws_secret_key', /(?i)aws_secret_access_key\s*[:=]\s*[\'"]?([A-Za-z0-9/+=]{40})[\'"]?/g],
            ['private_key', /-----BEGIN.*PRIVATE KEY-----/g],
            ['password', /(?i)(password|passwd|pwd)\s*[:=]\s*[\'"]?([^\s\'"]+)[\'"]?/g],
            ['email', /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g],
            ['credit_card', /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g],
            ['phone', /\b\d{3}[\s.-]?\d{3}[\s.-]?\d{4}\b/g],
        ]);
        // Replacement strings
        this.replacements = new Map([
            ['github_pat', '[REDACTED GITHUB TOKEN]'],
            ['slack_token', '[REDACTED SLACK TOKEN]'],
            ['bearer_token', '[REDACTED BEARER TOKEN]'],
            ['aws_access_key', '[REDACTED AWS ACCESS KEY]'],
            ['aws_secret_key', '[REDACTED AWS SECRET KEY]'],
            ['private_key', '[REDACTED PRIVATE KEY]'],
            ['password', '[REDACTED PASSWORD]'],
            ['email', '[REDACTED EMAIL]'],
            ['credit_card', '[REDACTED CREDIT CARD]'],
            ['phone', '[REDACTED PHONE]'],
        ]);
    }
    scan(content, mode = 'redact') {
        const matches = [];
        let maxSeverity = 'low';
        const severityLevels = { 'low': 1, 'medium': 2, 'high': 3, 'critical': 4 };
        // Scan for each pattern
        for (const [patternName, regex] of this.patterns) {
            let match;
            while ((match = regex.exec(content)) !== null) {
                const severity = this.getPatternSeverity(patternName);
                matches.push({
                    pattern: patternName,
                    matched: match[0],
                    severity,
                    position: [match.index, match.index + match[0].length]
                });
                if (severityLevels[severity] > severityLevels[maxSeverity]) {
                    maxSeverity = severity;
                }
            }
        }
        // Determine action
        if (matches.length === 0) {
            return {
                action: 'allowed',
                sanitized: content,
                matches: [],
                severity: 'low'
            };
        }
        // Critical patterns always blocked
        if (maxSeverity === 'critical' || mode === 'block') {
            return {
                action: 'blocked',
                sanitized: '[OUTPUT BLOCKED - SENSITIVE DATA DETECTED]',
                matches,
                severity: maxSeverity
            };
        }
        // Redact sensitive data
        let sanitized = content;
        for (const match of matches) {
            const replacement = this.replacements.get(match.pattern) || '[REDACTED]';
            sanitized = sanitized.replace(match.matched, replacement);
        }
        return {
            action: 'redacted',
            sanitized,
            matches,
            severity: maxSeverity
        };
    }
    getPatternSeverity(patternName) {
        const criticalPatterns = ['github_pat', 'slack_token', 'bearer_token', 'private_key'];
        const highPatterns = ['aws_access_key', 'aws_secret_key', 'password'];
        const mediumPatterns = ['email', 'credit_card', 'phone'];
        if (criticalPatterns.includes(patternName)) {
            return 'critical';
        }
        else if (highPatterns.includes(patternName)) {
            return 'high';
        }
        else if (mediumPatterns.includes(patternName)) {
            return 'medium';
        }
        else {
            return 'low';
        }
    }
}
//# sourceMappingURL=terminal-dlp.js.map