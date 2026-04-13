# Agent Farm - Phase 2 Detailed Planning

**Status**: Ready to Start  
**Estimated Duration**: 3-4 weeks  
**Start Date**: After PR #81 merge (week of April 15, 2026)  
**Team Size**: 1-2 engineers  

---

## Overview

Phase 2 expands the Agent Farm MVP from basic code analysis (CodeAgent + ReviewAgent) to a comprehensive system with advanced agents, semantic search, and enterprise integration capabilities.

### Phase 2 Objectives
1. Implement ArchitectAgent for system design analysis
2. Implement TestAgent for test generation and coverage
3. Advanced agent coordination (parallel execution, consensus)
4. Semantic code search functionality
5. Team RBAC agent profiles
6. Audit trail and decision history
7. GitHub Actions CI/CD integration

### Expected Outcomes
- 4 specialized agents fully operational (Coder, Reviewer, Architect, Tester)
- Semantic search across entire codebase
- Team-level access control for agents
- Complete audit trail of all recommendations
- GitHub Actions CI/CD agent support
- Performance benchmarks establishing baselines

---

## Detailed Feature Breakdown

### 1. ArchitectAgent Implementation

**Purpose**: Analyze system architecture, design patterns, and scalability

**Responsibilities**:
- API contract validation (REST, GraphQL interfaces)
- Design pattern detection (singleton, factory, observer, etc.)
- Scalability assessment for components
- Architecture consistency with ADRs
- Dependency graph analysis
- Circular dependency detection
- Module boundary violations

**Checks to Implement** (15-20 checks):

```typescript
class ArchitectAgent extends Agent {
  // API Design
  checkRestApiConsistency()     // Naming, versioning, status codes
  checkGraphQLSchemaCompliance() // Schema validation, query complexity
  validateContractVersioning()   // Semantic versioning
  
  // Design Patterns
  detectDesignPatterns()         // Find and classify patterns
  checkPatternCorrectness()      // Are patterns properly applied?
  
  // Scalability
  assessComponentScalability()   // Horizontal scaling capability
  detectBottlenecks()           // Performance-critical paths
  evaluateConcurrency()         // Thread-safety, race conditions
  
  // Architecture
  checkArchitectureAlignmentWithADRs()
  validateModuleBoundaries()    // Cross-module coupling
  detectCircularDependencies()  // Dependency issues
  
  // Integration
  validateDataFlowConsistency() // Request/response flow
  checkErrorPropagation()       // Error handling patterns
  assessTestability()           // How easy to test this module?
}
```

**Configuration**:
```json
{
  "specialization": "ARCHITECT",
  "analysisTypes": [
    "SYSTEM_DESIGN",
    "SCALABILITY",
    "API_CONTRACTS",
    "DESIGN_PATTERNS",
    "INTEGRATION"
  ],
  "severity": {
    "CRITICAL": ["circular_dependency", "memory_leak_pattern"],
    "WARNING": ["unused_interface", "tight_coupling"],
    "INFO": ["pattern_match", "design_suggestion"]
  }
}
```

**Integration Points**:
- CodeIndexer for dependency graph analysis
- VS Code for project file access
- Orchestrator for result aggregation
- Dashboard for visualization

**Testing Strategy**:
- Unit tests for each check (20+ tests)
- Integration tests with orchestrator
- Performance tests on large codebases
- Sample codebase with known issues for validation

**Estimated Effort**: 80-100 hours (3-4 days)

---

### 2. TestAgent Implementation

**Purpose**: Analyze test coverage, suggest test cases, identify gaps

**Responsibilities**:
- Code coverage analysis
- Missing test detection
- Edge case discovery
- Property-based testing suggestions
- Test quality assessment
- Performance test suggestions

**Checks to Implement** (15-20 checks):

```typescript
class TestAgent extends Agent {
  // Coverage Analysis
  analyzeCoverageGaps()         // Uncovered lines/branches
  detectUntestableCode()        // Code that's hard to test
  
  // Test Quality
  evaluateTestIsolation()       // Are tests independent?
  checkTestAssertion Quality()  // How specific are assertions?
  assessMockingStrategy()       // Are mocks used appropriately?
  
  // Edge Cases
  detectEdgeCases()             // null, empty, boundary values
  suggestParameterCombinations() // Property-based testing
  findRaceConditions()          // Concurrency edge cases
  
  // Performance
  suggestPerformanceTests()     // Large data, slow I/O
  detectSlowTestDetection()     // Flaky tests, race conditions
  
  // Maintainability
  checkTestMaintainability()    // Is test code clean?
  detectDuplicateTestLogic()    // DRY principle
  assessTestReadability()       // Can others understand?
}
```

**Configuration**:
```json
{
  "specialization": "TESTER",
  "analysisTypes": [
    "COVERAGE_ANALYSIS",
    "EDGE_CASES",
    "PERFORMANCE_TESTING",
    "TEST_QUALITY",
    "FLAKY_TEST_DETECTION"
  ],
  "thresholds": {
    "minCoverage": 80,
    "maxComplexity": 15,
    "flakiness": 0.05
  }
}
```

**Integration Points**:
- Code coverage tools (Istanbul, nyc)
- Test runners (Jest, Mocha integration)
- CodeIndexer for complexity analysis
- CI/CD pipeline for metrics

**Testing Strategy**:
- Unit tests for each check
- Coverage report parsing tests
- Edge case detection validation
- Sample test suites for verification

**Estimated Effort**: 80-100 hours (3-4 days)

---

### 3. Advanced Agent Coordination

**Objective**: Enable agents to work together intelligently

**Features**:

#### 3.1 Parallel Agent Execution
```typescript
class Orchestrator {
  async executeAgentsInParallel(task: Task): Promise<Result> {
    // Identify which agents can run in parallel
    const agentGroups = this.groupAgentsByDependencies(task)
    
    // Execute each group concurrently
    const groupResults = await Promise.all(
      agentGroups.map(group => this.executeGroup(group, task))
    )
    
    // Merge results maintaining independence
    return this.mergeResultsIntelligently(groupResults)
  }
}
```

**Workflow**:
1. CodeAgent and ReviewAgent can run in parallel (independent)
2. ArchitectAgent can run after CodeAgent (uses code structure)
3. TestAgent waits for CodeAgent and ReviewAgent (needs suggestions)
4. All results merged with confidence scores

#### 3.2 Consensus Mechanism
```typescript
// When agents disagree, use confidence scores
interface AgentOpinion {
  recommendation: string
  confidence: 0.0 | 1.0  // How certain is this agent?
  reasoning: string
  severity: Severity
}

class Consensus {
  // Consensus needed if agents disabled (CodeAgent says simplify, 
  // ArchitectAgent says it's pattern-correct)
  resolveConflict(opinions: AgentOpinion[]): Recommendation {
    const avgConfidence = mean(opinions.map(o => o.confidence))
    
    if (avgConfidence < 0.7) {
      // Flag for human review
      return { type: 'CONFLICTED', opinions }
    }
    
    // Otherwise take highest-confidence recommendation
    return maxBy(opinions, o => o.confidence)
  }
}
```

#### 3.3 Cross-Agent Insights
```typescript
// Agents learn from each other's findings
class OutcomeAggregator {
  // If ReviewAgent finds "missing error handling"
  // And CodeAgent found "missing try-catch"
  // → Flag as critical security issue
  
  linkFindings(reviewerFindings, coderFindings) {
    // Correlate findings across agents
    // Elevate severity if multiple agents flag same issue
    // Build confidence through consensus
  }
}
```

**Testing Strategy**:
- Coordination tests (20+ tests)
- Timing/performance tests
- Conflict resolution tests
- Result merging tests

**Estimated Effort**: 30-40 hours (1-2 days)

---

### 4. Semantic Code Search

**Purpose**: Find code by meaning, not exact syntax

**Implementation Approach**:
```typescript
class SemanticCodeSearch {
  // Build semantic index once during startup
  async buildIndex(workspace: string) {
    const files = await getAllFiles(workspace)
    
    for (const file of files) {
      const ast = parseFile(file)
      const embeddings = await generateEmbeddings(ast)
      
      this.index.add({
        file,
        fingerprint: cryptoHash(content),
        embedding: embeddings,
        symbols: extractSymbols(ast)
      })
    }
  }
  
  // Query by meaning
  async search(query: string): Promise<SearchResult[]> {
    const queryEmbedding = await generateEmbeddings(query)
    
    // Vector similarity search
    const similar = this.index.findNearest(queryEmbedding, topK: 10)
    
    // Rank by relevance
    return rankResults(similar)
  }
}
```

**Query Examples**:
```
'Find all API error handlers' 
→ Returns catch blocks, error middleware, exception handlers

'Find components that validate user input'
→ Returns validation functions, sanitizers, input guards

'Find expensive database queries'
→ Returns N+1 patterns, missing indexes, slow joins
```

**Search Capabilities**:
- Find similar functions/patterns
- Locate duplicate logic
- Discover related components
- Find examples of patterns
- Identify performance bottlenecks

**Integration Points**:
- CodeIndexer provides AST
- Dashboard for search UI
- Agents use for pattern detection
- GitHub Actions for CI/CD

**Testing Strategy**:
- Embedding quality tests
- Search accuracy tests
- Performance benchmarks
- Integration tests with agents

**Estimated Effort**: 40-60 hours (2-3 days)

---

### 5. Team RBAC Agent Profiles

**Purpose**: Control which agents teams can use, what they can analyze

**Configuration Structure**:
```json
{
  "profiles": {
    "viewer": {
      "agents": ["ReviewAgent"],
      "permissions": ["view-results"],
      "restrictions": ["cannot-fix-code"]
    },
    "developer": {
      "agents": ["CodeAgent", "ReviewAgent"],
      "permissions": ["view-results", "implement-suggestions"],
      "restrictions": ["no-architecture-changes"]
    },
    "architect": {
      "agents": ["ArchitectAgent", "CodeAgent", "ReviewAgent"],
      "permissions": ["all-analysis"],
      "restrictions": ["must-approve-major-changes"]
    },
    "admin": {
      "agents": ["all"],
      "permissions": ["all"],
      "restrictions": []
    }
  }
}
```

**Agent Access Control**:
```typescript
class AgentAccessControl {
  canUserRunAgent(user: User, agent: Agent): boolean {
    const userRole = getUserRole(user)
    const allowedAgents = this.config.profiles[userRole].agents
    return allowedAgents.includes(agent.name)
  }
  
  filterRecommendationsByRole(
    recommendations: Recommendation[],
    user: User
  ): Recommendation[] {
    // Viewers only see security issues
    // Developers see all except architecture
    // Architects see everything
    return recommendations.filter(r => 
      this.hasPermission(user, r.type)
    )
  }
}
```

**Audit Integration**:
- Log which agents ran and by whom
- Record which recommendations were accepted/rejected
- Track implementation of suggestions
- Generate team metrics

**Testing Strategy**:
- Permission matrix tests
- Role assignment tests
- Filtering accuracy tests
- Audit trail validation

**Estimated Effort**: 20-30 hours (1-2 days)

---

### 6. Audit Trail & Decision History

**Purpose**: Complete traceability of agent analysis and human decisions

**Data Model**:
```typescript
interface AuditEntry {
  id: string
  timestamp: Date
  
  // Who ran the analysis
  user: User
  role: UserRole
  
  // What was analyzed
  file: string
  changeSet?: string  // Git commit/branch
  
  // How was it analyzed
  agentsInvolved: Agent[]
  task: Task
  
  // What was found
  findings: Finding[]
  recommendations: Recommendation[]
  
  // What was done
  acceptance: {
    implemented: Finding[]
    rejected: Finding[]
    deferred: Finding[]
  }
  implementation?: {
    commit: string
    date: Date
    result: 'success' | 'partial' | 'reverted'
  }
}
```

**Queries**:
```typescript
// Metrics
getAgentEffectiveness(agent: Agent, timeRange: DateRange)
  → % of recommendations accepted and successfully implemented

// Trends
getMostCommonIssuesOverTime()
  → Track if quality is improving

// Team Analytics  
getTeamRiskProfile()
  → Which teams have more security issues?
  
// Historical Comparison
compareCodeQualityByVersion()
  → How has code quality evolved?
```

**Integration Points**:
- Dashboard for viewing history
- GitHub Actions for CI/CD tracking
- Team metrics/analytics
- Long-term trend analysis

**Testing Strategy**:
- Audit entry creation tests
- Query accuracy tests
- Data consistency tests
- Performance tests on large audit trails

**Estimated Effort**: 30-40 hours (1-2 days)

---

### 7. GitHub Actions CI/CD Integration

**Purpose**: Run agents automatically in PR workflows

**Implementation**:
```yaml
name: Agent Farm Code Analysis

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  agent-farm-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for proper analysis
      
      - name: Run CodeAgent
        run: |
          code-server-agent run --agent CodeAgent \
            --files ${{ github.event.pull_request.changed_files }}
      
      - name: Run ReviewAgent
        run: |
          code-server-agent run --agent ReviewAgent \
            --files ${{ github.event.pull_request.changed_files }}
      
      - name: Run ArchitectAgent
        run: |
          code-server-agent run --agent ArchitectAgent \
            --files ${{ github.event.pull_request.changed_files }}
      
      - name: Post Results to PR
        run: |
          code-server-agent report --format=github-comment \
            > comment.md
          
          gh pr comment ${{ github.event.pull_request.number }} \
            --body-file comment.md
```

**Features**:
- Automatic analysis on PRs
- Comment with findings on PR
- Block merge if critical issues
- Track metrics over time
- Integrate with required status checks

**Configuration**:
```yaml
# .agent-farm.yml
agents:
  CodeAgent:
    enabled: true
    blockIfCritical: false
  
  ReviewAgent:
    enabled: true
    blockIfCritical: true  # Block on security issues
  
  ArchitectAgent:
    enabled: true
    blockIfCritical: false
  
  TestAgent:
    enabled: true
    minCoverage: 80
    blockIfFailing: false

reporting:
  format: github-comment
  includeMetrics: true
  tagTeamLead: true
```

**Testing Strategy**:
- GitHub Actions workflow tests
- Comment parsing tests
- Status check integration tests
- End-to-end PR workflow tests

**Estimated Effort**: 30-40 hours (1-2 days)

---

## Implementation roadmap

### Week 1 (Days 1-3): ArchitectAgent
- Day 1: Core implementation + tests (15 checks)
- Day 2: Integration with orchestrator
- Day 3: Dashboard UI, documentation

### Week 2 (Days 4-6): TestAgent
- Day 1: Core implementation + tests (15 checks)
- Day 2: Coverage analysis integration
- Day 3: Dashboard UI, documentation

### Week 2-3 (Days 7-10): Advanced Coordination
- Day 1: Parallel execution
- Day 2: Consensus mechanism  
- Day 3: Cross-agent insights
- Day 4: End-to-end testing

### Week 3 (Days 11-13): Semantic Search
- Day 1-2: Embedding and indexing (40 hours)
- Day 3: Search UI and integration

### Week 3-4 (Days 14-18): Enterprise Features
- Day 1: RBAC profiles
- Day 2: Audit trail
- Day 3: GitHub Actions CI/CD
- Day 4: Testing and polish

---

## Success Criteria

**Phase 2 Complete When**:
- ✅ 4 agents fully implemented (Coder, Reviewer, Architect, Tester)
- ✅ 80+ checks across all agents
- ✅ Semantic search working on real codebases
- ✅ RBAC control enforced
- ✅ Audit trail tracking all analyses
- ✅ GitHub Actions integration live
- ✅ 90%+ test coverage
- ✅ Zero TypeScript errors
- ✅ Comprehensive documentation
- ✅ Performance benchmarks established

---

## Resource Requirements

**Team**:
- 1-2 engineers, 3-4 weeks
- 1 QA engineer (part-time, 1 week)
- 1 tech writer (part-time, 0.5 weeks)

**Infrastructure**:
- Development environment (existing)
- CI/CD pipeline (existing)
- Semantic search compute (~2GB RAM)

**Tools**:
- Jest for testing (existing)
- TypeScript (existing)
- Vector DB for semantic search (new: ~50MB)

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| **Performance degradation** | Profile all agents, cache results |
| **Semantic search accuracy** | Fine-tune embeddings, gather feedback |
| **Agent conflicts** | Implement consensus + human override |
| **Test coverage gaps** | 20+ tests per new feature |
| **Integration complexity** | Modular design, test in isolation first |

---

## Post-Phase-2 (Phase 3 Preview)

**Enterprise Integration** (weeks 5-7):
- Cross-repository agent coordination
- Enterprise analytics dashboard
- Team performance metrics
- Integration with issue management
- Slack notifications
- Advanced reporting

---

## Dependencies on Phase 1

✅ **All Phase 1 deliverables are blockers for Phase 2**:
- ✅ Agent base class (agent.ts)
- ✅ Orchestrator pattern (orchestrator.ts)
- ✅ CodeIndexer (code-indexer.ts)
- ✅ Dashboard UI foundation
- ✅ VS Code extension structure
- ✅ Test infrastructure (Jest)

**No new dependencies required** - Phase 2 extends existing architecture.

---

## Document Status

**Status**: Ready for Review  
**Last Updated**: April 12, 2026  
**Next Review**: After PR #81 merge  
**Approval Needed**: Engineering lead sign-off before Phase 2 starts

---

**Plan prepared by**: GitHub Copilot  
**Reviewed by**: (pending)  
**Approved by**: (pending)

