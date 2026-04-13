# Agent Farm MVP - Implementation Guide

## Overview

Agent Farm is a multi-agent development system that provides specialized AI agents for code analysis, optimization, and review. This MVP implementation includes:

- **CodeAgent**: Implementation analysis, refactoring opportunities, performance optimization
- **ReviewAgent**: Code quality checks, security audits, best practices enforcement
- **AgentOrchestrator**: Coordinates multiple agents and aggregates recommendations
- **VS Code Integration**: Dashboard UI, sidebar panel, commands, audit trail

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    VS Code Extension                         │
│                    (extension.ts/index.ts)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  AgentOrchestrator                           │
│            (Coordinates agents & aggregates results)         │
└─────────────────────────────────────────────────────────────┘
         │                           │
         ▼                           ▼
    ┌────────────┐            ┌──────────────┐
    │  CodeAgent │            │ ReviewAgent  │
    │ (coder)    │            │ (reviewer)   │
    └────────────┘            └──────────────┘
         │                           │
         └───────────┬───────────────┘
                     ▼
            ┌──────────────────┐
            │  Agent Base      │
            │  (Abstract)      │
            └──────────────────┘
```

### Data Flow

1. User runs command: `agentFarm.analyzeFile`
2. Extension retrieves current file content
3. Orchestrator routes task to appropriate agents based on TaskType
4. Each agent analyzes code independently
5. Results are aggregated and deduplicated
6. Dashboard renders findings with UI
7. Audit trail records analysis for history

## Files Structure

```
extensions/agent-farm/
├── src/
│   ├── agent.ts                 # Base agent class + interfaces
│   ├── orchestrator.ts          # Multi-agent coordinator
│   ├── code-indexer.ts          # Semantic code analysis
│   ├── dashboard.ts             # Webview UI
│   ├── index.ts                 # VS Code extension entry
│   ├── agents/
│   │   ├── code-agent.ts        # Implementation specialist
│   │   └── review-agent.ts      # Quality & security auditor
│   ├── types.ts                 # Shared type definitions
│   ├── orchestrator/           # Future: advanced coordination
│   ├── indexing/               # Future: semantic indexing
│   ├── ui/                     # Future: custom UI components
│   └── tests/                  # Unit & integration tests
├── package.json                 # Extension manifest
├── tsconfig.json               # TypeScript configuration
└── jest.config.js              # Test configuration
```

## Key Interfaces

### Agent Base Class

```typescript
abstract class Agent {
  analyze(documentUri, code, context?): Promise<Recommendation[]>
  execute(documentUri, code, context?): Promise<AgentResult>
  canHandle(taskType): boolean
  getMetadata(): AgentMetadata
}
```

### Recommendation

```typescript
interface Recommendation {
  id: string;
  title: string;
  description: string;
  severity: 'critical' | 'warning' | 'info';
  actionable: boolean;
  suggestedFix?: string;
  codeSnippet?: string;
  documentationUrl?: string;
}
```

### OrchestratorResult

```typescript
interface OrchestratorResult {
  documentUri: string;
  totalDuration: number;
  agentResults: AgentResult[];
  aggregatedRecommendations: Recommendation[];
  summary: {
    totalRecommendations: number;
    criticalCount: number;
    warningCount: number;
    infoCount: number;
    averageConfidence: number;
  };
}
```

## Task Types Supported

- `CODE_REVIEW`: General code quality review
- `CODE_IMPLEMENTATION`: Check implementation patterns
- `REFACTORING`: Identify refactoring opportunities
- `PERFORMANCE`: Analyze performance issues
- `SECURITY`: Security audit

## Agent Specializations

### CodeAgent (Coder)

Handles: Implementation, Refactoring, Performance

Checks:
- Missing error handling in async/await
- Console.log statements (suggest structured logging)
- Magic numbers (suggest named constants)
- Code duplication (suggest extraction)
- Long functions (suggest decomposition)
- Nested loops (suggest optimization)
- Synchronous file operations
- Recursive functions without memoization

### ReviewAgent (Reviewer)

Handles: Code Review, Security

Checks:
- Inconsistent naming conventions (camelCase vs snake_case)
- Insufficient code documentation
- Unresolved TODO/FIXME comments
- Hardcoded credentials (critical)
- SQL injection vulnerabilities
- eval() usage
- ReDoS regex patterns
- Loose equality (==) checks
- Vague error messages
- Mixed CommonJS/ES6 modules
- Unused variables

## Commands

| Command | Title | Shortcut |
|---------|-------|----------|
| `agentFarm.analyzeFile` | Analyze File | Ctrl+Shift+A |
| `agentFarm.analyzeWithTask` | Quick Analysis | - |
| `agentFarm.showDashboard` | Show Dashboard | - |
| `agentFarm.semanticSearch` | Semantic Search | - |
| `agentFarm.indexFile` | Index File | - |
| `agentFarm.listAgents` | List Agents | - |
| `agentFarm.showAuditTrail` | Show Audit Trail | - |
| `agentFarm.clearAuditTrail` | Clear Audit Trail | - |

## Usage Examples

### Analyze Current File

```
Command: Agent Farm: Analyze File
Result: Dashboard opens with recommendations
```

### Quick Analysis with Specific Task

```
Command: Agent Farm: Quick Analysis
Select: Code Review
Result: CodeAgent + ReviewAgent analyze file
```

### View Analysis History

```
Command: Agent Farm: Show Audit Trail
Select: Previous analysis
Result: Dashboard opens selected analysis
```

## Configuration

In VS Code settings (`settings.json`):

```json
{
  "agentFarm.enabled": true,
  "agentFarm.agents": ["CodeAgent", "ReviewAgent"],
  "agentFarm.maxConcurrentAgents": 2,
  "agentFarm.autoAnalyze": false,
  "agentFarm.analysisDelay": 1000,
  "agentFarm.maxRecommendations": 50,
  "agentFarm.auditTrail": true
}
```

## Dashboard UI

The dashboard provides:

- **Summary Statistics**: Critical count, warnings, info, average confidence
- **Agent Metrics**: Duration and confidence for each agent
- **Recommendations List**: Sorted by severity, with details and fixes
- **Audit Trail**: History of all analyses

## Extension Points

Agent Farm is designed for extensibility:

### Phase 2: Full System

```typescript
// Add ArchitectAgent
class ArchitectAgent extends Agent {
  // System design, API contracts, scalability analysis
}

// Add TestAgent
class TestAgent extends Agent {
  // Test coverage, edge cases, property-based testing
}
```

### Phase 3: Enterprise Integration

- GitHub Actions CI/CD agents
- Code review automation workflow
- Cross-repository coordination
- Enterprise analytics & reporting

## Performance Characteristics

- **Single-file analysis**: ~100-500ms (depends on file size)
- **Agent execution**: Parallel (both agents run simultaneously)
- **Dashboard rendering**: Instant
- **Audit trail**: In-memory (up to 100 analyses)

## Error Handling

All errors are:
1. Caught and logged to output channel
2. Displayed in error notification
3. Recorded in orchestrator logs
4. Never block user interface

## Security Considerations

- No code uploaded anywhere
- No external API calls
- Analysis happens locally
- Audit trail stored in memory only (not persisted)
- Credentials/secrets flagged as critical findings

## Testing

Run tests:

```bash
npm test
```

Test coverage includes:
- Agent analysis logic
- Orchestrator coordination
- Recommendation aggregation
- Code indexing
- Dashboard rendering

## Future Enhancements

- [ ] Semantic code search
- [ ] Team audit trail (persistent storage)
- [ ] RBAC team configuration
- [ ] Parallel agent execution with consensus
- [ ] Custom agent creation framework
- [ ] GitHub Actions integration
- [ ] VS Code Copilot Chat integration
- [ ] Real-time collaborative analysis
- [ ] ML-based severity ranking
- [ ] Project-wide analysis reports

## Related Issues

- **#80**: This implementation (Agent Farm MVP)
- **#79**: Base infrastructure (Copilot Chat + auth)
- **#75**: Branch protection (already complete Phase 1)

## Contributing

To add a new agent:

1. Extend the `Agent` base class
2. Implement the `analyze()` method
3. Register in `AgentOrchestrator.initializeAgents()`
4. Add tests in `src/tests/`
5. Update documentation

## License

MIT

## Support

For issues or feature requests, see: https://github.com/kushin77/code-server/issues
