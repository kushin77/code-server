# Phase 12: Advanced Observability & Distributed Tracing

## Overview

Phase 12 implements enterprise-grade distributed tracing, custom instrumentation, and advanced observability patterns to complement Phase 11's performance benchmarking. This enables deep visibility into request flows, dependency mapping, and performance bottleneck identification across the entire microservices ecosystem.

**Objectives:**
- ✅ Distributed tracing with Jaeger integration
- ✅ Request flow visualization and service dependency mapping
- ✅ Custom instrumentation for all services
- ✅ Performance profiling and flame graph generation
- ✅ Automated anomaly detection with tracing data
- ✅ Cost optimization via trace sampling strategies

---

## 1. Jaeger Distributed Tracing Setup

### 1.1 Kubernetes Deployment

```yaml
# kubernetes/base/jaeger.yaml

apiVersion: v1
kind: Namespace
metadata:
  name: observability

---
apiVersion: v1
kind: Service
metadata:
  name: jaeger-collector
  namespace: observability
spec:
  type: ClusterIP
  ports:
  - port: 14268
    name: http-collector
  - port: 14250
    name: grpc-collector
  - port: 6831
    name: jaeger-compact
    protocol: UDP
  selector:
    app: jaeger

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: observability
spec:
  replicas: 3
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:1.42
        ports:
        - containerPort: 6831
          protocol: UDP
        - containerPort: 14268
          protocol: TCP
        - containerPort: 14250
          protocol: TCP
        - containerPort: 16686
          protocol: TCP
        env:
        - name: COLLECTOR_ZIPKIN_HOST_PORT
          value: ":9411"
        - name: MEMORY_MAX_TRACES
          value: "10000"
        - name: SPAN_STORAGE_TYPE
          value: "elasticsearch"
        - name: ES_SERVER_URLS
          value: "http://elasticsearch:9200"
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /
            port: 16686
          initialDelaySeconds: 30
          periodSeconds: 10

---
apiVersion: v1
kind: Service
metadata:
  name: jaeger-ui
  namespace: observability
spec:
  type: LoadBalancer
  ports:
  - port: 16686
    targetPort: 16686
  selector:
    app: jaeger

---
# Elasticsearch for Jaeger span storage
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: jaeger-elasticsearch
  namespace: observability
spec:
  version: 8.11.0
  nodeSets:
  - name: default
    count: 3
    config:
      node.store.allow_mmap: false
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
```

### 1.2 OpenTelemetry Collector Configuration

```yaml
# kubernetes/base/otel-collector.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: observability
data:
  otel-collector-config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      jaeger:
        protocols:
          grpc:
            endpoint: 0.0.0.0:14250
          thrift_http:
            endpoint: 0.0.0.0:14268

    processors:
      batch:
        send_batch_size: 512
        timeout: 5s
      memory_limiter:
        check_interval: 1s
        limit_mib: 512
      attributes:
        actions:
        - key: environment
          value: production
          action: upsert
        - key: version
          from_attribute: service.version
          action: insert
      resource_detection:
        detectors: [gcp, env, system]

    exporters:
      jaeger:
        endpoint: jaeger-collector:14250
      prometheus:
        endpoint: 0.0.0.0:8889
      logging:
        loglevel: debug

    service:
      pipelines:
        traces:
          receivers: [otlp, jaeger]
          processors: [memory_limiter, batch, attributes, resource_detection]
          exporters: [jaeger, logging]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheus]

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: observability
spec:
  replicas: 3
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
      - name: otel-collector
        image: otel/opentelemetry-collector-contrib:0.88.0
        ports:
        - containerPort: 4317  # OTLP gRPC
        - containerPort: 4318  # OTLP HTTP
        - containerPort: 14250 # Jaeger gRPC
        - containerPort: 14268 # Jaeger Thrift HTTP
        - containerPort: 8889  # Prometheus metrics
        volumeMounts:
        - name: config
          mountPath: /etc/otel/config.yaml
          subPath: otel-collector-config.yaml
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      volumes:
      - name: config
        configMap:
          name: otel-collector-config

---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: observability
spec:
  type: ClusterIP
  ports:
  - port: 4317
    name: otlp-grpc
  - port: 4318
    name: otlp-http
  - port: 14250
    name: jaeger-grpc
  - port: 14268
    name: jaeger-thrift
  - port: 8889
    name: prometheus
  selector:
    app: otel-collector
```

---

## 2. Custom Instrumentation

### 2.1 Node.js Backend Instrumentation

```typescript
// backend/src/instrumentation.ts

import { NodeTracerProvider } from '@opentelemetry/node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-node';
import { JaegerExporter } from '@opentelemetry/exporter-trace-jaeger';
import { registerInstrumentations } from '@opentelemetry/instrumentation';

export function initializeTracing() {
  const provider = new NodeTracerProvider();

  const jaegerExporter = new JaegerExporter({
    serviceName: 'agent-api',
    host: process.env.JAEGER_HOST || 'localhost',
    port: parseInt(process.env.JAEGER_PORT || '6832'),
  });

  provider.addSpanProcessor(new BatchSpanProcessor(jaegerExporter));

  // Auto-instrumentation for common libraries
  registerInstrumentations({
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-fs': {
          enabled: false, // Disable fs to reduce noise
        },
      }),
    ],
  });

  provider.register();
}

export function getTracer(serviceName: string) {
  return require('@opentelemetry/api').trace.getTracer(serviceName);
}
```

### 2.2 Custom Spans for Business Logic

```typescript
// backend/src/middleware/tracing-middleware.ts

import { Request, Response, NextFunction } from 'express';
import { trace, context } from '@opentelemetry/api';
import { W3CTraceContextPropagator } from '@opentelemetry/core';

const tracer = trace.getTracer('agent-api');
const propagator = new W3CTraceContextPropagator();

export function tracingMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const ctx = propagator.extract(
    context.active(),
    req.headers,
    (h: any, k: string) => h[k]
  );

  return context.with(ctx, () => {
    const span = tracer.startSpan(`${req.method} ${req.path}`, {
      attributes: {
        'http.method': req.method,
        'http.url': req.url,
        'http.target': req.path,
        'http.host': req.hostname,
        'http.scheme': req.protocol,
        'http.client_ip': req.ip,
      },
    });

    context.with(
      trace.setSpan(context.active(), span),
      () => {
        res.on('finish', () => {
          span.setAttributes({
            'http.status_code': res.statusCode,
          });
          span.end();
        });

        next();
      }
    );
  });
}
```

### 2.3 Database Query Tracing

```typescript
// backend/src/database/traced-client.ts

import { Client } from 'pg';
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('agent-api-database');

export class TracedClient extends Client {
  async query(text: string, values?: any[]) {
    return tracer.startActiveSpan(`db.query`, (span) => {
      span.setAttributes({
        'db.system': 'postgresql',
        'db.statement': this.sanitizeQuery(text),
        'db.operation': this.extractOperation(text),
        'db.rows_affected': 0,
      });

      const startTime = Date.now();

      try {
        const result = super.query(text, values);
        
        result.then((res) => {
          const duration = Date.now() - startTime;
          span.setAttributes({
            'db.duration_ms': duration,
            'db.rows_affected': res.rowCount || 0,
          });
          span.end();
        });

        return result;
      } catch (error) {
        span.recordException(error as Error);
        span.setStatus({ code: 2, message: 'ERROR' });
        span.end();
        throw error;
      }
    });
  }

  private sanitizeQuery(query: string): string {
    // Remove sensitive values from query for security
    return query.replace(/('([^']*)')/g, '?');
  }

  private extractOperation(query: string): string {
    const match = query.match(/^\s*(\w+)\s/i);
    return match ? match[1].toUpperCase() : 'UNKNOWN';
  }
}
```

### 2.4 Cache Operation Tracing

```typescript
// backend/src/cache/traced-redis.ts

import { trace, context } from '@opentelemetry/api';
import Redis from 'ioredis';

const tracer = trace.getTracer('agent-api-cache');

export class TracedRedis extends Redis {
  get(key: string) {
    return tracer.startActiveSpan(`cache.get`, (span) => {
      span.setAttributes({
        'cache.key': key,
        'cache.system': 'redis',
      });

      const start = Date.now();
      const result = super.get(key);

      return result.then((value: any) => {
        const duration = Date.now() - start;
        span.setAttributes({
          'cache.hit': value !== null,
          'cache.duration_ms': duration,
        });
        span.end();
        return value;
      });
    });
  }

  set(key: string, value: string, ttl?: number) {
    return tracer.startActiveSpan(`cache.set`, (span) => {
      span.setAttributes({
        'cache.key': key,
        'cache.system': 'redis',
        'cache.ttl_seconds': ttl || 86400,
      });

      const start = Date.now();
      const result = ttl 
        ? super.setex(key, ttl, value)
        : super.set(key, value);

      return result.then(() => {
        const duration = Date.now() - start;
        span.setAttributes({
          'cache.duration_ms': duration,
        });
        span.end();
      });
    });
  }
}
```

---

## 3. Service Dependency Mapping

### 3.1 Automatic Dependency Discovery

```typescript
// monitoring/dependency-mapper.ts

import { trace } from '@opentelemetry/api';
import * as fs from 'fs';

interface ServiceDependency {
  service: string;
  dependsOn: string[];
  callCount: number;
  avgLatency: number;
  errorRate: number;
}

export class DependencyMapper {
  private dependencies: Map<string, Set<string>> = new Map();
  private callStats: Map<string, any> = new Map();

  analyzeTraces(traceFile: string): ServiceDependency[] {
    const traces = JSON.parse(fs.readFileSync(traceFile, 'utf-8'));
    const dependencies: ServiceDependency[] = [];

    for (const trace of traces) {
      this.mapSpanDependencies(trace.spans);
    }

    // Convert to dependency array
    for (const [service, deps] of this.dependencies.entries()) {
      dependencies.push({
        service,
        dependsOn: Array.from(deps),
        callCount: this.callStats.get(service)?.count || 0,
        avgLatency: this.callStats.get(service)?.avgLatency || 0,
        errorRate: this.callStats.get(service)?.errorRate || 0,
      });
    }

    return dependencies;
  }

  private mapSpanDependencies(spans: any[]) {
    for (let i = 0; i < spans.length; i++) {
      const span = spans[i];
      const nextSpan = spans[i + 1];

      if (nextSpan && this.isChildSpan(span, nextSpan)) {
        const service1 = this.extractService(span);
        const service2 = this.extractService(nextSpan);

        if (!this.dependencies.has(service1)) {
          this.dependencies.set(service1, new Set());
        }
        this.dependencies.get(service1)!.add(service2);

        // Track stats
        this.trackCallStats(service1, span);
      }
    }
  }

  private isChildSpan(parent: any, child: any): boolean {
    return child.parentSpanId === parent.spanId;
  }

  private extractService(span: any): string {
    return span.tags?.find((t: any) => t.key === 'service.name')?.value || 'unknown';
  }

  private trackCallStats(service: string, span: any) {
    if (!this.callStats.has(service)) {
      this.callStats.set(service, {
        count: 0,
        totalLatency: 0,
        errors: 0,
      });
    }

    const stats = this.callStats.get(service);
    stats.count += 1;
    stats.totalLatency += span.duration || 0;
    
    if (span.error) {
      stats.errors += 1;
    }

    stats.avgLatency = stats.totalLatency / stats.count;
    stats.errorRate = stats.errors / stats.count;
  }

  generateDependencyGraph(dependencies: ServiceDependency[]): string {
    let graph = 'digraph services {\n';

    for (const dep of dependencies) {
      for (const downstream of dep.dependsOn) {
        graph += `  "${dep.service}" -> "${downstream}";\n`;
      }
    }

    graph += '}\n';
    return graph;
  }
}
```

### 3.2 Dependency Visualization

```bash
#!/bin/bash
# monitoring/visualize-dependencies.sh

set -e

TRACE_FILE=${1:-traces.json}

# Generate dependency graph
node -e "
const mapper = require('./dependency-mapper');
const m = new mapper.DependencyMapper();
const deps = m.analyzeTraces('$TRACE_FILE');
const graph = m.generateDependencyGraph(deps);
console.log(graph);
" > dependencies.dot

# Convert to SVG
dot -Tsvg dependencies.dot > dependencies.svg

# Generate ASCII graph
echo "Service Dependencies:"
echo "===================="

node -e "
const mapper = require('./dependency-mapper');
const m = new mapper.DependencyMapper();
const deps = m.analyzeTraces('$TRACE_FILE');

deps.forEach(d => {
  console.log(\`\${d.service}:\`);
  d.dependsOn.forEach(dep => {
    console.log(\`  → \${dep} (\${d.avgLatency.toFixed(2)}ms avg, \${(d.errorRate*100).toFixed(2)}% errors)\`);
  });
});
"
```

---

## 4. Performance Profiling Integration

### 4.1 Flame Graph Generation

```bash
#!/bin/bash
# monitoring/generate-flamegraph.sh

SERVICE=${1:-agent-api}
DURATION=${2:-30}  # 30 seconds

echo "=== Generating Flame Graph for $SERVICE ==="

# Fetch traces from Jaeger during profiling window
curl -s "http://localhost:16686/api/traces?service=$SERVICE&limit=10000" \
  | jq '.data[] | {
    traceID,
    spans: [.spans[] | {
      operationName,
      duration: (.endTime - .startTime),
      processID
    }]
  }' > trace-data.json

# Convert to flame graph format
node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('trace-data.json'));

let stack = [];

data.forEach(trace => {
  trace.spans.forEach(span => {
    const depth = stack.filter(s => s.end > span.startTime).length;
    console.log(span.operationName + ';' + stack.map(s => s.name).join(';') + ' ' + span.duration);
  });
});
" > trace-stacks.txt

# Generate flame graph (requires flamegraph.pl)
./infra/tools/flamegraph.pl trace-stacks.txt | \
  ./infra/tools/flamegraph.pl --title "$SERVICE Flame Graph" > flamegraph.svg

echo "✅ Flame graph saved to flamegraph.svg"
```

### 4.2 Continuous Profiling (pprof Integration)

```go
// monitoring/profiling.go

package monitoring

import (
	"github.com/google/pprof/profile"
	"runtime/pprof"
	"runtime/trace"
	"os"
	"fmt"
)

func StartContinuousProfiling() {
	// CPU profiling
	cpuProfile, _ := os.Create("/var/profiles/cpu.prof")
	pprof.StartCPUProfile(cpuProfile)

	// Memory profiling
	go func() {
		for {
			memProfile, _ := os.Create(fmt.Sprintf("/var/profiles/mem-%d.prof", time.Now().Unix()))
			pprof.WriteHeapProfile(memProfile)
			time.Sleep(5 * time.Minute)
		}
	}()

	// Goroutine profiling
	go func() {
		for {
			goroutineProfile, _ := os.Create(fmt.Sprintf("/var/profiles/goroutine-%d.prof", time.Now().Unix()))
			pprof.Lookup("goroutine").WriteTo(goroutineProfile, 0)
			time.Sleep(1 * time.Minute)
		}
	}()

	// Execution trace
	traceFile, _ := os.Create("/var/profiles/trace.out")
	trace.Start(traceFile)
}
```

---

## 5. Span Sampling Strategy

### 5.1 Adaptive Sampling Configuration

```yaml
# kubernetes/base/sampling-config.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: sampling-strategies
  namespace: observability
data:
  sampling-strategies.json: |
    {
      "default_strategy": {
        "type": "probabilistic",
        "param": 0.1
      },
      "service_strategies": [
        {
          "service": "agent-api",
          "type": "probabilistic",
          "param": 0.5,
          "comment": "High traffic service, sample more"
        },
        {
          "service": "code-server",
          "type": "probabilistic",
          "param": 0.2,
          "comment": "Lower traffic, lower sample rate"
        },
        {
          "service": "embeddings",
          "type": "probabilistic",
          "param": 0.1,
          "comment": "Expensive service, lower rate"
        }
      ],
      "operation_strategies": [
        {
          "operation": "db.query",
          "type": "probabilistic",
          "param": 0.05,
          "comment": "Very high volume, aggressive sampling"
        },
        {
          "operation": "cache.get",
          "type": "probabilistic",
          "param": 0.01,
          "comment": "Extremely high volume"
        },
        {
          "operation": "error.*",
          "type": "always_sampled",
          "comment": "Always sample errors"
        }
      ]
    }
```

### 5.2 Cost Optimization with Sampling

```bash
#!/bin/bash
# monitoring/calculate-trace-costs.sh

echo "=== Trace Collection Cost Analysis ==="

# Query Jaeger for span count
SPAN_COUNT=$(curl -s "http://localhost:16686/api/service_operation_stats?service=agent-api" \
  | jq '.operationStats[].spanCount' \
  | awk '{sum+=$1} END {print sum}')

# Calculate storage
ESTIMATED_STORAGE_GB=$(echo "scale=2; $SPAN_COUNT * 0.001" | bc)

# At $0.023 per GB/month (AWS S3)
ESTIMATED_COST=$(echo "scale=2; $ESTIMATED_STORAGE_GB * 0.023" | bc)

echo "Daily Spans: $SPAN_COUNT"
echo "Estimated Monthly Storage: ${ESTIMATED_STORAGE_GB}GB"
echo "Estimated Monthly Cost: \$$ESTIMATED_COST"

# Calculate optimal sampling rate
DESIRED_COST=50  # $50/month target
OPTIMAL_SAMPLE_RATE=$(echo "scale=4; $ESTIMATED_COST / $DESIRED_COST" | bc)

echo ""
echo "To achieve $50/month cost target:"
echo "Recommended Sampling Rate: $OPTIMAL_SAMPLE_RATE (sample 1 in $(echo "scale=0; 1/$OPTIMAL_SAMPLE_RATE" | bc) spans)"
```

---

## 6. Advanced Anomaly Detection

### 6.1 Trace-Based Anomaly Detection

```typescript
// monitoring/anomaly-detector.ts

import { Trace } from 'jaeger-client';

interface AnomalyAlert {
  type: string;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  message: string;
  affectedService: string;
  tracingData: any;
}

export class AnomalyDetector {
  private baselineMetrics: Map<string, any> = new Map();

  detectAnomalies(traces: Trace[]): AnomalyAlert[] {
    const alerts: AnomalyAlert[] = [];

    for (const trace of traces) {
      // Detect latency spikes
      const latencyAlert = this.detectLatencySpiked(trace);
      if (latencyAlert) alerts.push(latencyAlert);

      // Detect error rate increases
      const errorAlert = this.detectErrorRateSpike(trace);
      if (errorAlert) alerts.push(errorAlert);

      // Detect resource exhaustion
      const resourceAlert = this.detectResourceExhaustion(trace);
      if (resourceAlert) alerts.push(resourceAlert);

      // Detect deadlock patterns
      const deadlockAlert = this.detectDeadlock(trace);
      if (deadlockAlert) alerts.push(deadlockAlert);

      // Detect cascading failures
      const cascadeAlert = this.detectCascadingFailure(trace);
      if (cascadeAlert) alerts.push(cascadeAlert);
    }

    return alerts;
  }

  private detectLatencySpiked(trace: Trace): AnomalyAlert | null {
    const p99Latency = this.calculateP99Latency(trace.spans);
    const baseline = this.baselineMetrics.get(`latency-${trace.spans[0].processID}`) || 500;

    if (p99Latency > baseline * 3) {  // 3x spike
      return {
        type: 'LATENCY_SPIKE',
        severity: 'HIGH',
        message: `Latency spiked from ${baseline}ms to ${p99Latency}ms`,
        affectedService: trace.spans[0].processID,
        tracingData: trace,
      };
    }

    return null;
  }

  private detectErrorRateSpike(trace: Trace): AnomalyAlert | null {
    const errorCount = trace.spans.filter(s => s.error).length;
    const errorRate = errorCount / trace.spans.length;
    const baseline = this.baselineMetrics.get(`error-${trace.spans[0].processID}`) || 0.01;

    if (errorRate > baseline * 5) {  // 5x increase
      return {
        type: 'ERROR_RATE_SPIKE',
        severity: 'CRITICAL',
        message: `Error rate increased from ${(baseline*100).toFixed(2)}% to ${(errorRate*100).toFixed(2)}%`,
        affectedService: trace.spans[0].processID,
        tracingData: trace,
      };
    }

    return null;
  }

  private detectResourceExhaustion(trace: Trace): AnomalyAlert | null {
    // Check for memory pressure indicators in span tags
    const memoryPressureSpans = trace.spans.filter(s =>
      s.tags?.some(t =>
        t.key === 'container.memory.usage_bytes' &&
        t.vNum > (8 * 1024 * 1024 * 1024)  // > 8GB
      )
    );

    if (memoryPressureSpans.length > 0) {
      return {
        type: 'RESOURCE_EXHAUSTION',
        severity: 'CRITICAL',
        message: `Memory pressure detected (>${8}GB)`,
        affectedService: trace.spans[0].processID,
        tracingData: trace,
      };
    }

    return null;
  }

  private detectDeadlock(trace: Trace): AnomalyAlert | null {
    // Look for circular wait patterns in span parents
    const parentMap = new Map<string, string>();

    for (const span of trace.spans) {
      if (span.parentSpanId) {
        parentMap.set(span.spanId, span.parentSpanId);
      }
    }

    // Check for cycles
    for (const [spanId, parentId] of parentMap.entries()) {
      let current = parentId;
      const visited = new Set<string>();

      while (current && !visited.has(current)) {
        if (current === spanId) {
          // Cycle detected
          return {
            type: 'DEADLOCK_PATTERN',
            severity: 'CRITICAL',
            message: 'Circular dependency detected in span execution',
            affectedService: trace.spans[0].processID,
            tracingData: trace,
          };
        }
        visited.add(current);
        current = parentMap.get(current);
      }
    }

    return null;
  }

  private detectCascadingFailure(trace: Trace): AnomalyAlert | null {
    // Check if failure spreads from one service to many others
    const failuresByService: Map<string, number> = new Map();

    for (const span of trace.spans) {
      if (span.error) {
        const service = span.processID;
        failuresByService.set(service, (failuresByService.get(service) || 0) + 1);
      }
    }

    // If multiple services are failing, likely cascading
    if (failuresByService.size > 3) {
      return {
        type: 'CASCADING_FAILURE',
        severity: 'CRITICAL',
        message: `Failures cascading across ${failuresByService.size} services`,
        affectedService: 'MULTI',
        tracingData: trace,
      };
    }

    return null;
  }

  private calculateP99Latency(spans: any[]): number {
    const latencies = spans.map(s => s.duration || 0).sort((a, b) => a - b);
    return latencies[Math.floor(latencies.length * 0.99)];
  }
}
```

---

## 7. Alerting Rules for Tracing Data

### 7.1 Prometheus Rules for Trace-Based Alerts

```yaml
# monitoring/prometheus-trace-rules.yaml

groups:
- name: tracing-alerts
  interval: 30s
  rules:
  
  # Alert on high trace P99 latency
  - alert: HighP99Latency
    expr: histogram_quantile(0.99, rate(span_duration_ms_bucket[5m])) > 1000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High P99 span latency ({{ $value }}ms)"
      description: "Service {{ $labels.service }} experiencing high latency"

  # Alert on high trace error rate
  - alert: HighTraceErrorRate
    expr: rate(span_errors_total[5m]) > 0.05
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High error rate in traces ({{ $value }})"
      description: "Service {{ $labels.service }} error rate exceeded 5%"

  # Alert on trace sampling loss (dropped spans)
  - alert: TraceSamplingLoss
    expr: rate(jaeger_collector_spans_dropped_total[5m]) > 100
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "Trace sampling loss detected ({{ $value }} spans/sec dropped)"
      description: "Jaeger collector dropping spans due to high volume"

  # Alert on trace collector queue depth
  - alert: TraceCollectorQueueFull
    expr: jaeger_collector_queue_length > 5000
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Trace collector queue building up ({{ $value }} pending)"

  # Alert on service dependency degradation
  - alert: ServiceDependencyDegradation
    expr: (rate(span_duration_ms_bucket{span_name="call_downstream"}[5m]) / rate(span_duration_ms_bucket{span_name="call_downstream"}[15m])) > 2
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Service dependency {{ $labels.service }} experiencing 2x latency increase"
```

---

## 8. Trace Visualization Dashboard

### 8.1 Grafana Dashboard for Tracing

```json
{
  "dashboard": {
    "title": "Distributed Tracing Overview",
    "tags": ["tracing", "observability"],
    "panels": [
      {
        "title": "Service Call Graph",
        "type": "nodeGraph",
        "datasource": "Jaeger",
        "targets": [
          {
            "expr": "jaeger_service_dependencies",
            "format": "graph"
          }
        ]
      },
      {
        "title": "Trace Latency Percentiles",
        "type": "timeseries",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "histogram_quantile(0.50, rate(span_duration_ms_bucket[5m]))",
            "legendFormat": "P50"
          },
          {
            "expr": "histogram_quantile(0.95, rate(span_duration_ms_bucket[5m]))",
            "legendFormat": "P95"
          },
          {
            "expr": "histogram_quantile(0.99, rate(span_duration_ms_bucket[5m]))",
            "legendFormat": "P99"
          }
        ]
      },
      {
        "title": "Span Error Rate by Service",
        "type": "timeseries",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(span_errors_total[5m]) by (service)"
          }
        ]
      },
      {
        "title": "Slowest Operations (Live)",
        "type": "table",
        "datasource": "Jaeger",
        "targets": [
          {
            "expr": "topk(10, rate(span_duration_ms_bucket[5m])) by (operation_name)"
          }
        ]
      },
      {
        "title": "Trace Sampling Rate",
        "type": "gauge",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "jaeger_sampling_rate"
          }
        ]
      },
      {
        "title": "Service Dependencies Map",
        "type": "nodeGraph",
        "datasource": "Jaeger",
        "targets": [
          {
            "expr": "jaeger_service_dependencies"
          }
        ]
      }
    ]
  }
}
```

---

## 9. Cost Analysis & Optimization

### 9.1 Trace Storage Cost Calculator

```bash
#!/bin/bash
# monitoring/trace-cost-analysis.sh

set -e

echo "=== Trace Storage Cost Analysis ==="

# Query current trace volume
TRACES_PER_DAY=$(curl -s "http://localhost:16686/api/service_operation_stats?service=*" \
  | jq '[.operationStats[].spanCount] | add')

TRACES_PER_MONTH=$((TRACES_PER_DAY * 30))

# Estimate storage (avg 2KB per span)
STORAGE_GB=$(echo "scale=2; $TRACES_PER_MONTH * 0.002 / 1024" | bc)

# Cloud costs (varies by provider)
echo "Daily Traces: $TRACES_PER_DAY"
echo "Monthly Traces: $TRACES_PER_MONTH"
echo "Estimated Storage: ${STORAGE_GB}GB"
echo ""
echo "Cloud Storage Costs (per month):"
echo "  GCP Cloud Trace: \$$(echo "scale=2; $TRACES_PER_MONTH * 0.05 / 1000000" | bc)"
echo "  Datadog: \$$(echo "scale=2; $TRACES_PER_MONTH * 0.10 / 1000000" | bc)"
echo "  Elastic APM: \$$(echo "scale=2; $TRACES_PER_MONTH * 0.03 / 1000000" | bc)"
echo "  Self-hosted (Jaeger): \$$(echo "scale=2; $STORAGE_GB * 0.023" | bc)"

echo ""
echo "Recommended Optimizations:"
echo "1. Enable tail-based sampling (10-20x cost reduction)"
echo "2. Set operation-level sampling rates (cache.get: 1%, critical ops: 100%)"
echo "3. Implement trace retention policies (7 days for hot, 30 for archive)"
echo "4. Use compression (3-5x storage reduction)"
```

### 9.2 Retention Policy Configuration

```yaml
# kubernetes/base/trace-retention.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: trace-retention-policy
  namespace: observability
data:
  retention-policy.yaml: |
    hot_storage:
      driver: elasticsearch
      retention: 7d
      indices:
        - jaeger-span-*
    warm_storage:
      driver: s3
      bucket: traces-archive
      retention: 30d
      prefix: warm/
    cold_storage:
      driver: glacier
      bucket: traces-archive
      retention: 1y
      prefix: cold/
    compression:
      enabled: true
      algorithm: zstd
      level: 9
```

---

## 10. Integration with Performance Benchmarks

### 10.1 Trace-Driven Performance Testing

```bash
#!/bin/bash
# benchmarks/trace-analysis.sh

set -e

echo "=== Correlating Benchmark Results with Traces ==="

# Run benchmark
k6 run benchmarks/baseline.js --out json=benchmark-results.json

# Extract slow operations
SLOW_OPERATIONS=$(jq -r '.metrics.http_req_duration | select(.p99 > 1000)' benchmark-results.json)

if [ -n "$SLOW_OPERATIONS" ]; then
  echo "⚠️  Detected slow operations during benchmark:"
  echo "$SLOW_OPERATIONS" | jq .

  # Query Jaeger for matching traces
  echo ""
  echo "Matching traces from Jaeger:"
  
  TRACE_ID=$(curl -s 'http://localhost:16686/api/traces?limit=1&service=code-server' \
    | jq -r '.data[0].traceID')

  curl -s "http://localhost:16686/api/traces/$TRACE_ID" | jq '.data.spans[] | {
    spanID,
    operationName,
    duration,
    tags
  }'
fi
```

---

## 11. Training & Runbook

### 11.1 Jaeger Usage Runbook

```markdown
# Debugging with Jaeger: Quick Reference

## Finding Root Cause of Latency

1. **Identify slow operation in Jaeger UI**
   - Service: agent-api
   - Operation: /api/execute
   - Sort by latency

2. **Examine span timeline**
   - Each bar = one span
   - Span width = duration
   - Identify widest span (bottleneck)

3. **Check span details**
   - Tags: operation details, error info
   - Logs: debug messages, error stack traces
   - Attributes: metadata

4. **Trace downstream dependencies**
   - Click "Find child spans"
   - See which service takes longest
   - Check database vs cache vs network

## Common Patterns

**High latency, no errors**: Check database indexes, cache misses
**Errors in downstream service**: Check service health, resource limits
**Intermittent slowness**: Check resource contention, GC pauses
**Cascading failures**: Check circuit breakers, retry policies

## Trace URL Format

```
http://jaeger-ui:16686/trace/{traceID}?uiEmphasisColor0={color}
```

Example:
```
http://localhost:16686/trace/1a2b3c4d5e6f?uiEmphasisColor0=ff0000
```
```

---

## 12. Success Criteria

- ✅ Jaeger deployed with 99.95% uptime
- ✅ All services instrumented with custom spans
- ✅ Service dependency graph automatically generated
- ✅ Trace sampling optimized for cost (<$100/month)
- ✅ Anomaly detection catching 95% of issues before customer impact
- ✅ Flame graphs generated automatically for profiling
- ✅ Cross-team debugging time reduced by 50%

---

## Next Steps

1. Deploy Jaeger to observability namespace
2. Instrument code-server backend
3. Instrument agent-api with OpenTelemetry
4. Create dependency map dashboard
5. Run load test and analyze traces
6. Optimize sampling rates
7. Create team runbook
8. Begin **Phase 13: Advanced Security & Supply Chain**

