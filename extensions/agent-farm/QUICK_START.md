# Agent Farm MVP - Quick Start Guide

## What is Agent Farm?

Agent Farm is a multi-agent AI system that provides specialized analysis for your code. Each agent is optimized for a specific domain:

- **CodeAgent**: Finds implementation issues, refactoring opportunities, and performance problems
- **ReviewAgent**: Performs security audits, quality checks, and best practices enforcement
- **Future**: ArchitectAgent, TestAgent (coming in Phase 2)

## Installation

Agent Farm is pre-installed in the code-server enterprise environment. No additional setup required!

## Getting Started

### 1. Open a File

Open any TypeScript, JavaScript, or code file in VS Code.

### 2. Run Analysis

**Option A: Quick Analysis**
```
Command Palette (Ctrl+Shift+P) → "Agent Farm: Analyze File"
```

**Option B: Choose Task Type**
```
Command Palette → "Agent Farm: Quick Analysis"
→ Select analysis type (Code Review, Performance, Security, etc.)
```

**Option C: Context Menu**
```
Right-click in editor → "Agent Farm: Analyze File"
Right-click in editor → "Agent Farm: Quick Analysis"
```

### 3. View Results

Results appear in the Agent Farm Dashboard showing:
- Summary statistics (critical, warnings, info)
- Agent metrics (confidence, duration)
- Detailed recommendations with suggested fixes

## Key Features

### 1. Multi-Agent Analysis
Each agent independently analyzes your code and identifies issues in its specialty area. Results are aggregated and deduplicated.

### 2. Severity-Based Sorting
Recommendations are automatically sorted by severity:
- 🔴 **Critical**: Security vulnerabilities, hardcoded credentials, dangerous operations
- 🟡 **Warning**: Code smells, performance issues, missing error handling
- 🔵 **Info**: Style suggestions, documentation improvements

### 3. Actionable Recommendations
Each finding includes:
- Clear title and description
- Suggested fix with code example
- Related documentation URL
- Actionable flag (can implement automation)

### 4. Audit Trail
View your analysis history:
```
Command Palette → "Agent Farm: Show Audit Trail"
```

### 5. Code Indexing
Understand your code structure:
```
Command Palette → "Agent Farm: Index File"
→ Shows function count, class count, complexity metrics
```

## What Each Agent Checks For

### CodeAgent Checks

**Implementation Issues:**
- Missing error handling on async/await
- Console.log statements (suggest structured logging)
- Magic numbers (suggest named constants)

**Refactoring Opportunities:**
- Code duplication (suggest extraction)
- Long functions (suggest decomposition)
- Improper abstraction

**Performance:**
- Nested loops (O(n²) complexity)
- Synchronous file operations (blocking)
- Recursive functions without memoization

### ReviewAgent Checks

**Code Quality:**
- Inconsistent naming conventions (camelCase vs snake_case)
- Insufficient documentation
- Unresolved TODO/FIXME comments

**Security (Critical):**
- Hardcoded credentials, API keys, tokens
- SQL injection vulnerabilities
- eval() usage
- Loose equality (==) checks
- ReDoS regex patterns

**Best Practices:**
- Vague error messages
- Mixed CommonJS/ES6 modules
- Unused variables

## Example Analysis

### Input Code
```javascript
const userId = 123;
const apiKey = "sk_live_abc123xyz";  // ❌ CRITICAL: Hardcoded credential!
function fetchUser(id) {
  const users = [
    { id: 1, name: "Alice" },
    { id: 2, name: "Bob" },
  ];
  for (let i = 0; i < users.length; i++) {
    if (users[i].id === id) {  // ❌ WARNING: Could be O(n) - use Map instead
      return users[i];
    }
  }
  return null;
}
```

### Results Output
**Critical Issues:** 1
- Hardcoded credentials detected (API key)
- **Fix**: Use environment variables (process.env.API_KEY)

**Warnings:** 1 
- Linear search in function (O(n) complexity)
- **Fix**: Use Map data structure for O(1) lookup

**Info:** 1
- Magic number "123" without constant
- **Fix**: const DEFAULT_USER_ID = 123;

## Commands Reference

| Command | Description |
|---------|-------------|
| Analyze File | Run full analysis on current file |
| Quick Analysis | Choose specific analysis type |
| Show Dashboard | Open/focus analysis results |
| Index File | Show code structure metrics |
| Semantic Search | Search code by meaning (Phase 2) |
| List Agents | Show available agents |
| Show Audit Trail | View analysis history |
| Clear Audit Trail | Reset history |

## Settings

Configure Agent Farm in VS Code settings:

```json
{
  "agentFarm.enabled": true,
  "agentFarm.autoAnalyze": false,          // Run on file save
  "agentFarm.analysisDelay": 1000,         // Delay before auto-analysis
  "agentFarm.maxRecommendations": 50,      // Limit displayed findings
  "agentFarm.enabledAgents": ["CodeAgent", "ReviewAgent"]
}
```

## Dashboard UI

The dashboard displays:

**Top Section:**
- File being analyzed
- Total analysis duration
- Number of agents used

**Summary Cards:**
- Critical count (red)
- Warning count (yellow)  
- Info count (blue)
- Average confidence (%)

**Agent Metrics:**
- Agent name and specialization
- Confidence percentage
- Execution duration (ms)

**Recommendations List:**
- Sorted by severity (critical → warning → info)
- Expandable details and suggested fixes
- Actionable flag indicator
- Related documentation links

## Best Practices

### 1. Run Regularly
Analyze files as you work to catch issues early.

### 2. Focus on Critical
Address critical issues (especially security) first.

### 3. Review Suggestions
Not all suggestions apply - review them for your context.

### 4. Check Documentation
Use provided documentation links to understand issues better.

### 5. Integrate with CI/CD
Future Phase 3 will integrate with GitHub Actions for automated analysis.

## Troubleshooting

### No recommendations found?
This means your code is excellent! 🎉

### Agent took too long?
Agent Farm typically completes in 100-500ms. Very large files (>10,000 lines) may take longer. Consider splitting into smaller modules.

### Dashboard not updating?
Try running analysis again (Ctrl+Shift+P → "Analyze File")

### Missing agent output?
Check the Agent Farm output channel:
```
View → Output → Select "Agent Farm: CodeAgent" or "Agent Farm: ReviewAgent"
```

## Roadmap

### Phase 1 (Current - MVP)
✅ CodeAgent + ReviewAgent
✅ Dashboard UI
✅ Audit Trail
✅ Code Indexing

### Phase 2 (Coming Soon)
- [ ] ArchitectAgent (system design analysis)
- [ ] TestAgent (test coverage analysis)
- [ ] Semantic code search
- [ ] Advanced coordination (parallel agents)
- [ ] Team RBAC configuration

### Phase 3 (Enterprise)
- [ ] GitHub Actions CI/CD integration
- [ ] Cross-repository analysis
- [ ] Persistent audit trail
- [ ] Enterprise analytics & reporting

## Support

For issues or feature requests:
- GitHub Issues: https://github.com/kushin77/code-server/issues
- Reference Issue #80 for Agent Farm feature tracking

## Architecture

For technical details on Agent Farm architecture, see:
- `extensions/agent-farm/IMPLEMENTATION.md` - Full technical documentation
- `extensions/agent-farm/src/` - Source code
- `extensions/agent-farm/package.json` - Extension manifest

Enjoy better code! 🚀
