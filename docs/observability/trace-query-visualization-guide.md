# Trace Query and Visualization Guide

**Phase**: 13 - Trace Analysis & Insights  
**Audience**: SREs, observability engineers, and debugging workflows  
**Scope**: searching traces, grouping results, and building visual views

The query and visualization helpers let you search traces by service, operation,
duration, status, and time range, then reshape the result into views that are
useful for troubleshooting and product analysis.

## Modules

### `apps/shared/trace_query.py`
Use this module when you need to search or aggregate trace records.

- `TraceQuery` builds structured filters and paging options
- `TraceQueryEngine` evaluates those filters against trace data
- `TraceAggregator` groups traces by service, operation, or status

### `apps/shared/trace_visualization.py`
Use this module when you need a renderable representation of trace activity.

- `Timeline` produces span lanes with depth information
- `FlameGraph` builds hierarchical call stacks
- `ServiceMap` captures service-to-service dependencies
- `SequenceDiagram` captures actor interactions

## Common Workflows

1. Query traces for a service or operation of interest.
2. Aggregate the result to understand error rates or latency distribution.
3. Convert the trace data into a timeline, flame graph, service map, or sequence diagram.
4. Feed the rendered output into the debugging or incident review workflow.

## Practical Notes

- Use `TraceQuery` for repeatable searches instead of ad hoc filtering logic.
- Use the timeline and flame graph models when you need order and causality.
- Use the service map when the question is about dependency shape rather than a single trace.