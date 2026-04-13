"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Agent = void 0;
class Agent {
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
exports.Agent = Agent;
//# sourceMappingURL=types.js.map