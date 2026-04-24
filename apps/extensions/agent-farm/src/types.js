export class Agent {
    log(message) {
        console.log(`[${this.name}] ${message}`);
    }
    formatOutput(summary, recommendations = [], severity = 'info') {
        return {
            agentName: this.name,
            domain: this.domain,
            timestamp: new Date(),
            summary,
            recommendations,
            severity,
        };
    }
}
//# sourceMappingURL=types.js.map