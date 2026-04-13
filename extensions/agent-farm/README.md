# Agent Farm - Multi-Agent Development System

A VS Code extension implementing a team of specialized AI agents for code analysis, review, architecture design, and testing.

## Quick Start

### Installation & Setup

```bash
cd extensions/agent-farm
npm install
npm run compile
```

### Run Tests

```bash
# Run full test suite with coverage
npm test

# Run tests in watch mode
npm run test:watch

# Check test coverage
npm run test:coverage
```

### Development

```bash
# Watch mode - auto-recompile on changes
npm run watch

# Launch extension in debug mode
Press F5 in VS Code
```

## Architecture

### Four-Agent System

```
┌─ CodeAgent (Implementation)
│  └─ Refactoring, complexity analysis, tech debt detection
│
├─ ReviewAgent (Quality)
│  └─ Code review, security vulnerabilities, error handling
│
├─ ArchitectAgent (Design)
│  └─ Design patterns, API contracts, scalability
│
└─ TestAgent (Testing)
   └─ Test coverage, untested paths, test recommendations
```

### Key Components

- **Orchestrator**: Intelligent task routing based on input type
- **CodeIndexer**: Semantic analysis and code understanding
- **DashboardManager**: Real-time results display in VS Code webview
- **TypeSystem**: Complete TypeScript interfaces for type safety

## Commands

### Available VS Code Commands

1. **agent-farm.executeTask**
   - Route task to specialized agents
   - Triggered: Command Palette or menu

2. **agent-farm.showDashboard**
   - Display agent farm status and results
   - Triggered: Command Palette or sidebar

3. **agent-farm.semanticSearch**
   - Search code by meaning
   - Triggered: Command Palette with input

4. **agent-farm.analyzeFile**
   - Run all agents on current file
   - Triggered: Command Palette or keyboard shortcut

## Configuration

Configure behavior in VS Code settings (`settings.json`):

```json
{
  "agentFarm.enabled": true,
  "agentFarm.agents": ["code", "review", "architect", "test"],
  "agentFarm.maxConcurrentAgents": 2,
  "agentFarm.auditTrail": true
}
```

## Testing

### Test Structure

- `src/tests/testUtils.ts` - Mock generators and test utilities
- `src/tests/agents.test.ts` - Individual agent tests
- `src/tests/orchestrator.test.ts` - Integration tests
- `jest.config.js` - Jest configuration with coverage thresholds

### Running Tests

```bash
# Run all tests
npm test

# Run specific test file
npm test -- agents.test.ts

# Watch mode
npm run test:watch

# Coverage report
npm run test:coverage
```

### Coverage Targets

- **Global**: 70%+ coverage
- **Branches**: 60%+
- **Functions**: 70%+
- **Statements**: 70%+

## Build & Release

### Compile to JavaScript

```bash
npm run compile
```

This generates `out/` directory with compiled JavaScript.

### Create VSIX Package

```bash
npm install -g vsce
vsce package
```

Output: `agent-farm-*.vsix`

### Publish to VS Code Marketplace

```bash
# Login first
vsce login

# Publish
vsce publish
```

## CI/CD

### GitHub Actions

Automated workflows in `.github/workflows/agent-farm-ci.yml`:

1. **Test** (on push/PR)
   - Install dependencies
   - Lint TypeScript
   - Run tests
   - Upload coverage

2. **Build** (on test success)
   - Compile TypeScript
   - Create VSIX package
   - Upload as artifact

3. **Release** (on version tags)
   - Create GitHub release
   - Attach VSIX file

### Running Locally

```bash
# Trigger test workflow
git push origin feat/agent-farm

# Check workflow status
gh workflow view "Agent Farm CI/CD" --repo kushin77/code-server
```

## Project Structure

```
extensions/agent-farm/
├── src/
│   ├── agents/           # Agent implementations
│   │   ├── CodeAgent.ts
│   │   ├── ReviewAgent.ts
│   │   ├── ArchitectAgent.ts
│   │   └── TestAgent.ts
│   ├── orchestrator/
│   │   └── Orchestrator.ts
│   ├── indexing/
│   │   └── CodeIndexer.ts
│   ├── ui/
│   │   └── DashboardManager.ts
│   ├── tests/
│   │   ├── testUtils.ts
│   │   ├── agents.test.ts
│   │   └── orchestrator.test.ts
│   ├── extension.ts      # Entry point
│   └── types.ts          # Type definitions
├── out/                  # Compiled JavaScript (generated)
├── .vscode/
│   ├── launch.json       # Debug configuration
│   └── tasks.json        # Build tasks
├── package.json
├── tsconfig.json
├── jest.config.js
└── README.md
```

## Performance

### Agent Execution Time

- CodeAgent: ~50-100ms per file
- ReviewAgent: ~50-100ms per file
- ArchitectAgent: ~30-50ms per file
- TestAgent: ~50-100ms per file
- Total: ~150-350ms for 4 agents

### Memory Usage

- Extension load: ~8-12 MB
- Per analysis: +2-5 MB (temporary)
- Dashboard: ~3-5 MB

## Troubleshooting

### npm install fails

```bash
# Use legacy peer deps flag
npm install --legacy-peer-deps
```

### TypeScript compilation errors

```bash
# Clear compiled output and recompile
rm -rf out/
npm run compile
```

### Tests not running

```bash
# Rebuild TypeScript first
npm run compile
npm test
```

### Extension not loading in VS Code

1. Check extension logs: `View > Output > Agent Farm`
2. Verify TypeScript compiled: `ls -la out/`
3. Reload VS Code: `Cmd+Shift+P` → "Developer: Reload Window"

## Development Guide

### Adding New Agent

1. Create `src/agents/NewAgent.ts`
2. Implement `Agent` interface
3. Add to `extension.ts` initialization
4. Add routing in `Orchestrator.selectAgent()`
5. Add tests in `src/tests/agents.test.ts`

### Modifying Dashboard

1. Edit `src/ui/DashboardManager.ts`
2. Update HTML generation in `generateHTML()`
3. CSS is embedded in HTML
4. Recompile: `npm run compile`

### Adding Tests

1. Create test file with `.test.ts` suffix
2. Use `TestUtils` for mock data
3. Jest auto-discovers and runs
4. Run: `npm test`

## Contributing

1. Create feature branch: `git checkout -b feat/feature-name`
2. Make changes and test: `npm test`
3. Compile: `npm run compile`
4. Push: `git push origin feat/feature-name`
5. Create PR with test results

## License

MIT - See LICENSE file

## Support

For issues, see: https://github.com/kushin77/code-server/issues/80

---

**Agent Farm MVP - Bringing specialized AI agents to VS Code developers** 🤖
