# Execution Scheduler Service

Task scheduling and job orchestration system for Code Server Enterprise. Manages delayed execution, recurring jobs, batch processing, and temporal event coordination across the platform.

## Architecture Overview

Execution Scheduler provides:

- **Job Scheduling**: One-time and recurring job execution with flexible scheduling
- **Task Queue Management**: Distributed queue for job processing
- **Temporal Coordination**: Time-based event triggers and scheduling rules
- **Job State Tracking**: Persistent job state with status transitions
- **Error Handling**: Retry policies, dead-letter jobs, failure recovery
- **Scalable Execution**: Horizontal scaling with distributed job processing
- **Audit Trail**: Complete job execution history and metrics

### Job Types

```yaml
# One-Time Jobs
- name: "one_time"
  example: "Send password reset email in 5 minutes"
  schedule: "2026-04-28T10:05:00Z"
  max_duration_seconds: 300
  retry_policy: "exponential_backoff"

# Recurring Jobs
- name: "recurring_daily"
  example: "Cleanup old logs every day at 2 AM"
  schedule: "0 2 * * *"  # Cron format
  timezone: "UTC"

# Recurring Weekly
- name: "recurring_weekly"
  example: "Generate weekly reports every Monday at 9 AM"
  schedule: "0 9 * * 1"  # Monday

# Recurring Monthly
- name: "recurring_monthly"
  example: "Archive old events every 1st at 00:00"
  schedule: "0 0 1 * *"

# Batch Processing
- name: "batch_job"
  example: "Process 10,000 events in parallel batches"
  batch_size: 100
  parallel_batches: 10

# Delayed Job
- name: "delayed_job"
  example: "Trigger incident response in 30 seconds"
  delay_seconds: 30
```

## Service Dependencies

```
execution-scheduler
├── PostgreSQL (scheduler_db, jobs table)
├── Redis (job queue, locks)
├── Kafka (job events, completion notifications)
├── control-plane (authorization)
├── reputation_engine (tier-based job submission limits)
└── Executor Workers (30+ instances for parallel processing)
```

## Core Components

### 1. Job Scheduler

```python
# Example: Create a one-time job
POST /jobs
{
    "job_type": "send_email",
    "scheduled_time": "2026-04-28T10:05:00Z",
    "payload": {
        "recipient": "user@company.com",
        "subject": "Password Reset",
        "template": "password_reset"
    },
    "priority": "normal",
    "tags": ["user-action", "authentication"]
}

Response:
{
    "job_id": "job-20260428-001",
    "status": "scheduled",
    "scheduled_time": "2026-04-28T10:05:00Z",
    "created_at": "2026-04-28T10:00:00Z",
    "estimated_duration_seconds": 5,
    "queue_position": 42
}
```

### 2. Job Queue Manager

```python
# Example: Get next job for processing
GET /queue/pop?worker_id=worker-12

Response:
{
    "job_id": "job-20260428-001",
    "job_type": "send_email",
    "payload": {...},
    "created_at": "2026-04-28T10:00:00Z",
    "scheduled_time": "2026-04-28T10:05:00Z",
    "attempt": 1,
    "max_attempts": 3,
    "timeout_seconds": 300
}
```

### 3. Job State Machine

```python
# Job lifecycle states
states = {
    "created": "Job created, waiting to be queued",
    "scheduled": "Job scheduled for future execution",
    "queued": "Job in execution queue",
    "processing": "Job actively being processed",
    "completed": "Job completed successfully",
    "failed": "Job processing failed",
    "retry": "Job failed, scheduled for retry",
    "dead_letter": "Job failed after max retries",
    "cancelled": "Job was cancelled by user"
}

# Transitions
created → scheduled → queued → processing → completed
         → queued → processing → failed → retry → queued
         → dead_letter (after max retries)
         → cancelled (user action)
```

### 4. Recurring Job Manager

```python
# Example: Create recurring job
POST /jobs/recurring
{
    "job_type": "cleanup_logs",
    "schedule": "0 2 * * *",  # Daily at 2 AM UTC
    "timezone": "UTC",
    "payload": {
        "retention_days": 30,
        "pattern": "/var/log/services/*.log"
    },
    "retry_policy": {
        "max_attempts": 3,
        "backoff_multiplier": 2,
        "initial_delay_seconds": 60
    }
}

Response:
{
    "recurring_job_id": "recurr-20260428-001",
    "job_type": "cleanup_logs",
    "schedule": "0 2 * * *",
    "timezone": "UTC",
    "status": "active",
    "next_execution": "2026-04-29T02:00:00Z",
    "execution_history": []
}
```

### 5. Batch Processing Engine

```python
# Example: Submit batch job
POST /jobs/batch
{
    "job_type": "process_events",
    "total_items": 10000,
    "batch_size": 100,
    "parallel_batches": 5,
    "payload_template": {
        "service": "reputation_engine",
        "action": "update_scores"
    },
    "item_generator": {
        "type": "kafka_topic",
        "topic": "user.activity",
        "consumer_group": "batch-processor-001"
    }
}

Response:
{
    "batch_job_id": "batch-20260428-001",
    "total_items": 10000,
    "batch_size": 100,
    "parallel_batches": 5,
    "estimated_duration_seconds": 300,
    "progress": {
        "completed": 0,
        "in_progress": 0,
        "pending": 100
    }
}
```

## API Endpoints

### Job Management

```bash
# Create job
POST /jobs
{
    "job_type": "type-name",
    "scheduled_time": "2026-04-28T10:05:00Z",
    "payload": {...}
}

# Get job status
GET /jobs/{job_id}

# List jobs
GET /jobs?status=processing&limit=50&offset=0

# Cancel job
DELETE /jobs/{job_id}

# Get job execution history
GET /jobs/{job_id}/history
```

### Recurring Jobs

```bash
# Create recurring job
POST /jobs/recurring
{
    "job_type": "type-name",
    "schedule": "0 2 * * *",
    "timezone": "UTC",
    "payload": {...}
}

# List recurring jobs
GET /jobs/recurring?status=active

# Update recurring job
PUT /jobs/recurring/{recurring_job_id}
{
    "schedule": "0 3 * * *"
}

# Pause/Resume recurring job
PUT /jobs/recurring/{recurring_job_id}/status
{
    "status": "paused|active"
}
```

### Batch Processing

```bash
# Submit batch job
POST /jobs/batch
{
    "job_type": "type-name",
    "total_items": 10000,
    "batch_size": 100,
    "parallel_batches": 5,
    "payload_template": {...}
}

# Get batch progress
GET /jobs/batch/{batch_job_id}/progress

# Cancel batch job
DELETE /jobs/batch/{batch_job_id}
```

### Queue Management

```bash
# Pop job from queue (worker endpoint)
GET /queue/pop?worker_id={worker_id}

# Report job completion
POST /queue/complete
{
    "job_id": "{job_id}",
    "status": "success|failure",
    "output": {...},
    "error": "error message if failed"
}

# Get queue metrics
GET /queue/metrics
{
    "queue_length": 1234,
    "average_wait_time_seconds": 45,
    "processing_rate_per_second": 23.5,
    "workers_active": 15,
    "workers_idle": 5
}
```

### Health & Status

```bash
# Scheduler health
GET /health

Response:
{
    "status": "healthy",
    "queue_depth": 1234,
    "active_workers": 15,
    "jobs_processed_last_hour": 5432,
    "average_job_duration_seconds": 12,
    "failed_jobs_last_hour": 23,
    "dead_letter_queue_size": 5
}
```

## Configuration

### Environment Variables

```bash
# Database
SCHEDULER_DB_URL=postgresql://user:pass@localhost:5432/scheduler_db
SCHEDULER_DB_POOL_SIZE=20

# Redis
SCHEDULER_REDIS_URL=redis://localhost:6379/0
SCHEDULER_REDIS_QUEUE_PREFIX=job:queue:

# Job Configuration
SCHEDULER_DEFAULT_MAX_ATTEMPTS=3
SCHEDULER_DEFAULT_TIMEOUT_SECONDS=300
SCHEDULER_DEFAULT_RETRY_DELAY_SECONDS=60
SCHEDULER_MAX_BATCH_SIZE=1000
SCHEDULER_MAX_PARALLEL_BATCHES=10

# Worker Configuration
SCHEDULER_WORKER_COUNT=10
SCHEDULER_WORKER_POLL_INTERVAL_SECONDS=1
SCHEDULER_WORKER_IDLE_TIMEOUT_SECONDS=300

# Kafka (for job events)
SCHEDULER_KAFKA_BOOTSTRAP_SERVERS=kafka:9092
SCHEDULER_KAFKA_TOPIC_JOB_EVENTS=scheduler.events

# Job Retention
SCHEDULER_COMPLETED_JOB_RETENTION_DAYS=30
SCHEDULER_FAILED_JOB_RETENTION_DAYS=90
```

### Docker Compose Configuration

```yaml
execution-scheduler:
  image: kushin77/code-server-execution-scheduler@sha256:mno345...
  ports:
    - "8013:8000"
  environment:
    - SCHEDULER_DB_URL=postgresql://postgres:password@postgres:5432/scheduler_db
    - SCHEDULER_REDIS_URL=redis://redis:6379/0
    - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    - SCHEDULER_WORKER_COUNT=10
    - SCHEDULER_DEFAULT_MAX_ATTEMPTS=3
  depends_on:
    - postgres
    - redis
    - kafka
  volumes:
    - /var/log/scheduler:/var/log/scheduler
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
```

## Retry Policies

### Exponential Backoff

```python
{
    "policy": "exponential_backoff",
    "max_attempts": 3,
    "initial_delay_seconds": 60,
    "backoff_multiplier": 2,
    "max_delay_seconds": 3600
}

# Retry timeline:
# Attempt 1: Immediate
# Attempt 2: After 60 seconds
# Attempt 3: After 120 seconds
# Attempt 4: After 240 seconds
# Max: 3600 seconds (1 hour)
```

### Linear Backoff

```python
{
    "policy": "linear_backoff",
    "max_attempts": 5,
    "delay_increment_seconds": 30
}

# Retry timeline:
# Attempt 1: Immediate
# Attempt 2: After 30 seconds
# Attempt 3: After 60 seconds
# Attempt 4: After 90 seconds
# Attempt 5: After 120 seconds
```

### Immediate Retry

```python
{
    "policy": "immediate",
    "max_attempts": 3
}

# Attempt immediately without delay
```

## Integration Examples

### Control Plane Integration

```python
# Schedule deployment validation job
POST /jobs
{
    "job_type": "validate_deployment",
    "scheduled_time": "2026-04-28T10:00:00Z",
    "payload": {
        "deployment_id": "dep-001",
        "service": "auth-server"
    },
    "tags": ["deployment"],
    "timeout_seconds": 120
}

# Completion triggers control-plane notification
POST control-plane/deployments/dep-001/validation-complete
```

### Reputation Engine Integration

```python
# Schedule reputation score update
POST /jobs/recurring
{
    "job_type": "update_reputation_scores",
    "schedule": "0 * * * *",  # Every hour
    "payload": {
        "include_decays": true
    }
}

# Reports completion to reputation_engine
```

### Activity Feed Integration

```python
# All job events published to activity feed
POST activity-feed/events
{
    "event_type": "job_completed",
    "job_id": "job-001",
    "job_type": "send_email",
    "status": "success",
    "duration_seconds": 5,
    "timestamp": "2026-04-28T10:05:05Z"
}
```

## Monitoring & Observability

### Key Metrics

```
# Job Metrics
scheduler_jobs_created_total
scheduler_jobs_completed_total
scheduler_jobs_failed_total
scheduler_jobs_in_queue
scheduler_job_duration_seconds
scheduler_job_wait_time_seconds

# Queue Metrics
scheduler_queue_depth
scheduler_queue_processing_rate
scheduler_worker_utilization_percent
scheduler_worker_active_count

# Retry Metrics
scheduler_job_retries_total
scheduler_job_retry_rate
scheduler_dead_letter_queue_size

# Batch Metrics
scheduler_batch_job_progress_percent
scheduler_batch_items_processed_total
scheduler_batch_duration_seconds
```

## Production Deployment Checklist

- [ ] PostgreSQL 14+ with automated backups
- [ ] Redis 7+ with persistence
- [ ] Kafka 7+ for event publishing
- [ ] Worker nodes deployed (10+ recommended)
- [ ] Job type handlers implemented
- [ ] Retry policies configured
- [ ] Dead-letter queue strategy defined
- [ ] Monitoring and alerting configured
- [ ] Backup procedures tested
- [ ] Disaster recovery plan documented
- [ ] Load testing completed
- [ ] Team training completed

## Troubleshooting

### Jobs Stuck in Processing State

```bash
# Check worker status
curl http://scheduler:8013/queue/metrics

# Check specific job
curl http://scheduler:8013/jobs/job-001

# If worker crashed, mark job as failed and requeue
POST /jobs/job-001/force-requeue
{
    "reason": "worker_failure"
}
```

### Queue Not Processing

```bash
# Check queue depth
curl http://scheduler:8013/queue/metrics

# Verify workers are running
docker ps | grep scheduler-worker

# Check Redis connection
redis-cli -h redis ping

# Check database
psql -c "SELECT COUNT(*) FROM scheduler_db.jobs WHERE status='queued';"
```

## Related Services

- **control-plane**: Orchestration scheduling
- **reputation_engine**: Scheduled score updates
- **activity_feed**: Job event streaming
- **event-bus**: Publish job completion events

## Support & Documentation

For additional support, see:

- [Job Scheduling Guide](../../DEPLOYMENT_EXECUTION_PLAN.md)
- [Production Deployment](../../DEPLOYMENT_READINESS_FINAL.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: scheduling

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026  
**Maintainer**: Code Server Enterprise Team
