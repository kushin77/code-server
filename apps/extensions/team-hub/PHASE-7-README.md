# P2 #1539 Phase 7: Advanced Team Coordination

**Phase 7 - Final Phase of IDE Intelligence Epic**

`Phase 7: Advanced Team Coordination` delivers ML-driven team collaboration, workload optimization, and performance insights for the KC IDE platform.

## Overview

Advanced Team Coordination automates intelligent task distribution, capacity planning, and team performance optimization using machine learning and real-time analytics.

### What's New in Phase 7

- **ML-Based Task Routing**: Intelligent assignment of tasks to team members based on skills, availability, and historical performance
- **Capacity Forecasting**: Predictive modeling of team member and team-wide capacity for upcoming sprints
- **Automated Workload Balancing**: Detect and resolve workload imbalances with recommendation algorithms
- **Performance Analytics**: Real-time tracking of team metrics with trend analysis and predictive insights
- **Seamless VS Code Integration**: Dashboard, commands, and status bar for easy access

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│         Advanced Team Coordination Orchestrator          │
│  (Coordinates all modules and publishes to Kafka)       │
└─────────────────────────────────────────────────────────┘
         │                    │                   │
         ▼                    ▼                   ▼
    ┌─────────┐          ┌──────────┐      ┌──────────┐
    │ ML Task │          │ Capacity │      │ Workload │
    │ Router  │          │Forecaster│      │ Balancer │
    └─────────┘          └──────────┘      └──────────┘
         │                    │                   │
         └────────┬───────────┴───────────┬───────┘
                  │                       │
                  ▼                       ▼
          ┌──────────────┐      ┌─────────────────┐
          │ PostgreSQL   │      │ Kafka Event Bus │
          │  (Metrics)   │      │  (Audit Trail)  │
          └──────────────┘      └─────────────────┘
                  │                       │
                  └───────────┬───────────┘
                              │
                              ▼
                 ┌──────────────────────────┐
                 │ Performance Tracker      │
                 │ (Trend Analysis)         │
                 └──────────────────────────┘
```

## Core Modules

### 1. ML Task Router (`ml-task-router.ts`)

Intelligent task assignment using multi-factor scoring model.

**Features:**
- **Capability Matching** (40%): Technical skills alignment
- **Availability Scoring** (20%): Time zone and schedule fit
- **Capacity Assessment** (20%): Current workload analysis
- **Performance Scoring** (15%): Historical quality and velocity
- **Collaboration Factors** (5%): Team dynamics for pair programming

**Usage:**
```typescript
const router = new MLTaskRouter(kafkaProducer);

// Register team member with skills
await router.registerTeamMember({
  memberId: 'eng-001',
  name: 'Alice Chen',
  skills: new Map([['TypeScript', 95], ['React', 90]]),
  languages: ['English', 'Mandarin'],
  frameworks: ['React', 'Express', 'Next.js'],
  specializations: ['Frontend', 'Performance'],
  yearsOfExperience: 5,
});

// Route a task
const decision = await router.routeTask({
  taskId: 'task-123',
  title: 'Implement dashboard',
  description: '...',
  requiredSkills: new Map([['React', 80]]),
  estimatedHours: 16,
  priority: 'high',
  deadline: new Date('2026-05-01'),
});

// Returns routing decision with:
// - selectedMemberId: 'eng-001'
// - finalScore: 87.5
// - scoreBreakdown with component scores
// - alternativeCandidates with backup options
// - auditId for tracking
```

### 2. Capacity Forecaster (`capacity-forecaster.ts`)

Predictive modeling of team capacity using time series analysis.

**Features:**
- **Availability Forecasts**: Predict when team members are working
- **Capacity Predictions**: Estimate available story points
- **Confidence Intervals**: 10%, 50%, 90% certainty levels
- **Burndown Projections**: Will we meet sprint deadlines?
- **Bottleneck Detection**: Identify constraints

**Usage:**
```typescript
const forecaster = new CapacityForecaster(kafkaProducer);

// Record historical capacity data
forecaster.recordCapacityDataPoint('eng-001', {
  date: new Date(),
  storyPoints: 25,
  completed: true,
  utilizationPercentage: 92,
  activeTaskCount: 3,
});

// Forecast member capacity (14 days ahead)
const memberForecast = await forecaster.forecastMemberCapacity('eng-001', 14);
// Returns:
// - totalCapacityPoints: 140
// - availableCapacity: 45
// - utilizationTrend with daily estimates
// - confidenceInterval: { low: 120, medium: 130, high: 140 }

// Forecast team capacity
const teamForecast = await forecaster.forecastTeamCapacity(
  ['eng-001', 'eng-002', 'eng-003'],
  14
);
// Returns team-wide aggregates + burndown projection
```

### 3. Workload Balancer (`workload-balancer.ts`)

Automated workload optimization to minimize bottlenecks.

**Features:**
- **Multiple Strategies**: Round-robin, skill-based, load-balanced, fair-share
- **Imbalance Detection**: Identify over/under-utilized team members
- **Rebalancing Recommendations**: Specific task reallocation suggestions
- **Context Switch Minimization**: Batch similar tasks
- **Trend Analysis**: Historical workload patterns

**Usage:**
```typescript
const balancer = new WorkloadBalancer(kafkaProducer);

// Record workload snapshot
const snapshot = {
  timestamp: new Date(),
  members: [
    { memberId: 'eng-001', name: 'Alice', utilization: 105, ... },
    { memberId: 'eng-002', name: 'Bob', utilization: 35, ... },
  ],
  // ... more fields
};

// Analyze and generate recommendations
const recommendation = await balancer.analyzeAndRebalance(
  snapshot,
  'load-balanced'
);
// Returns:
// - currentImbalance: 70
// - projectedImbalance: 25 (after rebalancing)
// - rebalancingActions: [{ taskId, fromMemberId, toMemberId, reason, ... }]
// - improvementPercentage: 65%
// - contextSwitchReduction: 20%
```

### 4. Performance Tracker (`team-performance-tracker.ts`)

Real-time team metrics and predictive insights.

**Features:**
- **Individual Metrics**: Velocity, quality, reliability, collaboration
- **Team Metrics**: Throughput, cycle time, predictability, efficiency
- **Trend Analysis**: Spot improvements or degradation
- **Insights Generation**: Automatic detection of patterns and risks
- **Predictive Analytics**: Forecast future performance

**Usage:**
```typescript
const tracker = new TeamPerformanceTracker(kafkaProducer);

// Record individual metrics
await tracker.recordIndividualMetrics({
  memberId: 'eng-001',
  memberName: 'Alice Chen',
  period: { startDate: new Date('2026-04-21'), endDate: new Date('2026-05-04') },
  velocity: 32,
  qualityScore: 94,
  reliabilityScore: 100,
  collaborationScore: 85,
  tasksCompleted: 8,
  averageCycleTime: 18,
  bugEscapeRate: 2.5,
});

// Get performance summary
const summary = tracker.getIndividualSummary('eng-001', 4);
// { current: {...}, trend: {...}, historicalAverage: {...} }

// Get recent insights
const insights = tracker.getRecentInsights(10);
// [{type: 'trend', severity: 'medium', title: 'Velocity Declining', ...}]

// Predict future performance
const predictions = tracker.predictFuturePerformance('eng-001', 2);
// [{sprintAhead: 1, predictedVelocity: 30, confidence: 95}, ...]
```

### 5. Orchestrator (`advanced-team-coordination-orchestrator.ts`)

Coordinates all modules and provides VS Code integration.

**Features:**
- **Command Palette Integration**: Submit tasks, view metrics
- **Status Bar**: Quick team overview
- **Dashboard Panel**: Visual monitoring
- **Unified Workflow**: Route → Forecast → Balance → Track

## REST API Endpoints

All modules expose REST endpoints on designated ports:

### ML Task Router (Port 8090)
```
POST   /route               - Route a task to best member
GET    /history            - Get routing decision history
GET    /scores/:memberId   - Get member routing scores
```

### Capacity Forecaster (Port 8091)
```
GET    /forecast/member/:memberId  - Forecast member capacity
GET    /forecast/team              - Forecast team capacity
```

### Workload Balancer (Port 8092)
```
POST   /balance            - Analyze and rebalance workload
GET    /trend              - Get workload trend analysis
```

### Performance Tracker (Port 8093)
```
GET    /member/:memberId        - Get member performance
GET    /team/:teamId            - Get team performance
GET    /insights                - Get performance insights
POST   /compare                 - Compare two members
GET    /predict/:memberId       - Predict future performance
```

## Kafka Event Stream

All decisions and metrics are published to Kafka for immutable audit trail:

**Topics:**
- `team.routing.decisions` - Task routing decisions
- `team.capacity.forecast` - Capacity predictions
- `team.workload.recommendations` - Rebalancing recommendations
- `team.performance.individual` - Individual metrics
- `team.performance.aggregate` - Team metrics
- `team.performance.insights` - Generated insights
- `team.coordination.decisions` - Orchestration decisions
- `team.ops.setup_events` - Setup operations

## VS Code Integration

### Commands
- `advanced-team-coordination.show-dashboard` - Open coordination dashboard
- `advanced-team-coordination.submit-task` - Submit task for routing
- `advanced-team-coordination.view-routing` - View routing history
- `advanced-team-coordination.view-capacity` - View capacity forecasts
- `advanced-team-coordination.view-performance` - View performance metrics

### Status Bar
Shows current team size and active task count.

## Configuration

Create `.config/team-coordination/team-coordination.env`:

```env
# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=team_coordination

# Kafka
KAFKA_BOOTSTRAP_SERVERS=localhost:9092

# ML Models
ML_UPDATE_INTERVAL=3600
ROUTING_STRATEGY=load-balanced

# Performance Tracking
PERF_METRICS_RETENTION_DAYS=90
```

## Setup

Run the idempotent setup script:

```bash
bash scripts/ide/setup-advanced-team-coordination.sh production
```

This will:
- Initialize PostgreSQL schema
- Create Kafka topics
- Generate configuration files
- Register service endpoints
- Verify all components

## GOV-002 Compliance

All components follow governance standards:

✅ **Deterministic**: Consistent algorithms, no randomness  
✅ **Audited**: All decisions logged and published to Kafka  
✅ **Immutable**: Configuration-driven behavior  
✅ **Immutable Records**: Kafka event trail for compliance  

### Audit Fields

Every decision includes:
- `decisionId` / `forecastId` / `insightId`: Unique identifier
- `timestamp`: When decision was made
- `auditId` / `recordedAt`: Audit trail reference
- `headers` in Kafka: Routing context and model version

## Metrics & KPIs

### Individual Performance
- **Velocity**: Story points completed per sprint
- **Quality Score**: 0-100 based on bugs and reviews
- **Reliability**: % of on-time completions
- **Collaboration**: Pair programming and mentoring contribution

### Team Performance
- **Throughput**: Total points delivered
- **Cycle Time**: Average time task-to-complete
- **Predictability**: Accuracy of estimates (0-100)
- **Efficiency**: Points per person-hour

### Health Metrics
- **Workload Imbalance**: 0-100 (0 = perfect balance)
- **Utilization**: 0-100% (target: 75-85%)
- **Context Switches**: Reduction % from rebalancing

## Troubleshooting

**No team members registered:**
```bash
# Use orchestrator.registerTeamMember() to register members
# Or load from external system via integration point
```

**Capacity forecasts showing 0:**
```bash
# Record historical capacity data using recordCapacityDataPoint()
# Forecasts improve with historical data (>7 days recommended)
```

**Rebalancing recommendations show no actions:**
```bash
# Workload is already balanced
# Review utilization distribution in workload snapshot
```

**Performance insights not generating:**
```bash
# Need at least 2 periods of data for trend analysis
# Check individual_metrics and team_metrics tables in PostgreSQL
```

## Testing

Unit tests included in `apps/extensions/team-hub/tests/`:

```bash
npm test --prefix apps/extensions/team-hub
```

Tests cover:
- Routing algorithm correctness
- Capacity forecasting accuracy
- Workload balancing optimization
- Performance metric calculations
- Orchestration workflow

## Integration Points

### With Other P2 #1539 Phases
- **Phase 1 (KC IDE Branding)**: Unified dashboard theme
- **Phase 2 (Copilot Autonomy)**: Context injection from routing decisions
- **Phase 3 (Collaboration Intelligence)**: Pair programming detection
- **Phase 4 (Local Folder Access)**: Member workspace integration
- **Phase 5 (GitHub OAuth)**: GitHub issue routing
- **Phase 6 (Team Communication)**: Slack notifications for decisions

### With P3 Services
- **P3 #1559 (Reputation Engine)**: Tier-based access control
- **P3 #1557 (Agent Runtime)**: Task routing for agents
- **P3 #1561 (Execution Scheduler)**: Integration with task scheduler

### With External Systems
- **GitHub**: PR assignment via routing
- **Jira/Linear**: Issue routing and assignment
- **Slack**: Notifications and team presence
- **Time tracking**: Integration for actual vs estimated hours

## Performance Characteristics

- **Routing Decision**: ~100-200ms (single task)
- **Capacity Forecast**: ~500-1000ms (14 days, single member)
- **Workload Rebalancing**: ~1-5s (full team analysis)
- **Insight Generation**: ~2-10s (historical analysis)

## Future Enhancements

- **Real-time collaboration signals** from VS Code editor
- **Custom ML model training** based on team data
- **Burndown optimization** algorithms
- **Team dynamics learning** for improved pairing
- **Mobile app** for on-the-go monitoring
- **Executive dashboards** for leadership visibility

## License & Attribution

P2 #1539 Phase 7: Advanced Team Coordination  
GOV-002 Compliant Infrastructure  
Autonomous Infrastructure System  
April 26, 2026

---

**Documentation Version**: 1.0.0  
**Last Updated**: 2026-04-26  
**Status**: Production Ready
