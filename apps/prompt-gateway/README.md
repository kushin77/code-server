# Prompt Gateway Service

AI prompt orchestration and optimization service. Routes language model requests, manages prompt templates, optimizes model selection, and coordinates multi-LLM interactions for Code Server Enterprise.

## Architecture Overview

Prompt Gateway provides:

- **Prompt Routing**: Intelligent routing to optimal LLM based on request characteristics
- **Template Management**: Centralized prompt templates with variable substitution
- **Model Selection**: Automatic or manual model routing (GPT-4, Claude, Ollama)
- **Prompt Optimization**: Enhance prompts with context and examples
- **Caching**: Cache common prompt responses to reduce API costs
- **Rate Limiting**: Per-user and per-model rate limiting
- **Cost Optimization**: Route to cheaper models when appropriate
- **Compliance**: Content filtering and audit logging

## Core Components

### 1. Prompt Router

```python
# Example: Route prompt to optimal model
POST /route
{
    "prompt": "Explain async/await in JavaScript",
    "context": {
        "user_tier": "senior",
        "domain": "code",
        "complexity": "intermediate",
        "language": "javascript"
    },
    "routing_preference": "cost|speed|quality"
}

Response:
{
    "routing_id": "route-001",
    "selected_model": "gpt-4",
    "fallback_models": ["claude-3", "ollama-mixtral"],
    "estimated_cost": 0.15,
    "estimated_latency_ms": 1200,
    "temperature": 0.7,
    "max_tokens": 2048
}
```

### 2. Template Engine

```python
# Example: Use prompt template
POST /templates/apply
{
    "template_id": "code_review_template",
    "variables": {
        "language": "Python",
        "code": "def fibonacci(n):\n    return n if n < 2 else fib(n-1) + fib(n-2)",
        "focus_areas": ["performance", "readability"]
    }
}

Response:
{
    "template_id": "code_review_template",
    "rendered_prompt": "Review the following Python code for performance and readability...",
    "model_suggestion": "claude-3",
    "estimated_tokens": 450,
    "cache_hit": false
}
```

### 3. Model Selection Engine

```python
# Example: Get model recommendations
GET /models/recommendations?task=code_review&budget=0.50&latency_max_ms=5000

Response:
{
    "recommendations": [
        {
            "model": "gpt-4",
            "cost_per_1k_tokens": 0.03,
            "latency_p95_ms": 1200,
            "score": 0.95,
            "reason": "Best quality for code review"
        },
        {
            "model": "claude-3",
            "cost_per_1k_tokens": 0.02,
            "latency_p95_ms": 800,
            "score": 0.92,
            "reason": "Good quality, faster"
        },
        {
            "model": "ollama-mixtral",
            "cost_per_1k_tokens": 0.00,
            "latency_p95_ms": 600,
            "score": 0.70,
            "reason": "Free but lower quality"
        }
    ]
}
```

### 4. Prompt Cache

```python
# Example: Get cached response
GET /cache/lookup
{
    "prompt_hash": "sha256:abc123...",
    "model": "gpt-4",
    "age_acceptable_minutes": 60
}

Response:
{
    "cache_hit": true,
    "response": {
        "content": "...",
        "tokens_used": 450,
        "cost": 0.15
    },
    "cached_at": "2026-04-28T09:00:00Z",
    "age_minutes": 45
}
```

## API Endpoints

### Prompt Routing

```bash
# Route prompt to optimal model
POST /route
{
    "prompt": "...",
    "context": {...}
}

# Get routing history
GET /routes?user_id=user-001&limit=50

# Get route metrics
GET /routes/{routing_id}/metrics
```

### Template Management

```bash
# List templates
GET /templates?category=code_review

# Get template details
GET /templates/{template_id}

# Create custom template
POST /templates
{
    "name": "custom_template",
    "category": "code_review",
    "system_prompt": "...",
    "user_prompt_template": "Review {language} code for {focus_areas}"
}

# Apply template
POST /templates/{template_id}/apply
{
    "variables": {...}
}
```

### Model Management

```bash
# List available models
GET /models

# Get model configuration
GET /models/{model_id}

# Get model recommendations
GET /models/recommendations
{
    "task": "code_review",
    "budget": 0.50,
    "latency_max_ms": 5000
}
```

### Caching

```bash
# Get cached response
GET /cache/lookup
{
    "prompt_hash": "...",
    "model": "..."
}

# Clear cache entry
DELETE /cache/{cache_key}

# Get cache statistics
GET /cache/stats
```

## Configuration

### Environment Variables

```bash
# LLM Endpoints
OPENAI_API_KEY=sk-...
OPENAI_API_URL=https://api.openai.com/v1
CLAUDE_API_KEY=sk-ant-...
CLAUDE_API_URL=https://api.anthropic.com

# Ollama (Local)
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_MODELS=mixtral:7b,neural-chat:7b

# Routing
PROMPT_GATEWAY_ROUTING_STRATEGY=cost|speed|quality
PROMPT_GATEWAY_DEFAULT_MODEL=gpt-4

# Caching
PROMPT_GATEWAY_ENABLE_CACHE=true
PROMPT_GATEWAY_CACHE_TTL_HOURS=24
PROMPT_GATEWAY_CACHE_MAX_SIZE_GB=50

# Rate Limiting
PROMPT_GATEWAY_RATE_LIMIT_REQUESTS_PER_MINUTE=100
PROMPT_GATEWAY_RATE_LIMIT_TOKENS_PER_DAY=1000000

# Cost Control
PROMPT_GATEWAY_MAX_COST_PER_REQUEST=0.50
PROMPT_GATEWAY_MONTHLY_BUDGET_USD=5000
```

### Docker Compose Configuration

```yaml
prompt-gateway:
  image: kushin77/code-server-prompt-gateway@sha256:stu901...
  ports:
    - "8015:8000"
  environment:
    - OPENAI_API_KEY=${OPENAI_API_KEY}
    - OLLAMA_BASE_URL=http://ollama:11434
    - PROMPT_GATEWAY_ROUTING_STRATEGY=cost
  depends_on:
    - redis
    - ollama
  volumes:
    - /var/cache/prompt-gateway:/var/cache
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
```

## Built-in Prompt Templates

### Code Review Template

```
System: You are an expert code reviewer focusing on {focus_areas}.

Code to Review:
{code}

Language: {language}
Context: {context}

Provide a detailed code review addressing:
1. Performance implications
2. Code readability and maintainability
3. Security considerations
4. Best practices and patterns
5. Suggested improvements with code examples
```

### Documentation Template

```
System: You are a technical documentation expert.

Topic: {topic}
Target Audience: {audience}
Technical Level: {technical_level}

Generate comprehensive documentation including:
1. Overview and purpose
2. Architecture overview
3. Usage examples
4. Configuration guide
5. Troubleshooting section
6. Related resources
```

### Bug Analysis Template

```
System: You are a debugging expert with deep knowledge of {language}.

Error Message: {error_message}
Stack Trace: {stack_trace}
Code Context: {code_context}

Analyze and provide:
1. Root cause identification
2. Why this error occurred
3. Step-by-step fix procedure
4. Code example of the fix
5. Prevention strategies
```

## Model Configuration Examples

### GPT-4 Configuration

```yaml
model: gpt-4
api_provider: openai
cost_per_1k_tokens: 0.03
latency_p95_ms: 1200
max_tokens: 8192
temperature_range: [0, 2]
optimal_for:
  - complex reasoning
  - high quality output
  - code generation
  - analysis tasks
```

### Claude 3 Configuration

```yaml
model: claude-3
api_provider: anthropic
cost_per_1k_tokens: 0.02
latency_p95_ms: 800
max_tokens: 200000
context_window: 200k
optimal_for:
  - long context handling
  - document analysis
  - creative writing
  - conversation
```

### Ollama Local Configuration

```yaml
model: mixtral:7b
api_provider: ollama
cost_per_1k_tokens: 0.00
latency_p50_ms: 200
latency_p95_ms: 600
max_tokens: 4096
optimal_for:
  - low cost scenarios
  - offline operation
  - private data
  - fast responses
```

## Cost Optimization

### Tiered Response Strategy

```python
# User tier affects model selection
{
    "restricted": {
        "default_model": "ollama-mixtral",
        "max_cost_per_request": 0.01
    },
    "standard": {
        "default_model": "claude-3",
        "max_cost_per_request": 0.10
    },
    "senior": {
        "default_model": "gpt-4",
        "max_cost_per_request": 0.50
    },
    "elite": {
        "default_model": "gpt-4",
        "max_cost_per_request": 5.00,
        "allow_multi_model": true
    }
}
```

### Smart Caching

- Cache responses for identical prompts
- Reuse similar prompt responses with minor modifications
- Batch similar requests for single API call
- Estimated savings: 40-60% on repeated queries

## Monitoring & Observability

### Key Metrics

```
prompt_gateway_requests_total
prompt_gateway_request_latency_ms
prompt_gateway_cache_hit_rate
prompt_gateway_cost_per_request
prompt_gateway_model_utilization_percent
prompt_gateway_error_rate
prompt_gateway_monthly_cost_usd
```

## Production Deployment Checklist

- [ ] All LLM API keys securely stored in secrets manager
- [ ] Rate limiting configured appropriately
- [ ] Cost budgets set and monitored
- [ ] Cache storage provisioned
- [ ] Ollama local models available
- [ ] Monitoring and alerting configured
- [ ] Compliance scanning enabled
- [ ] Audit logging enabled
- [ ] Team trained on template creation
- [ ] Cost tracking enabled

## Related Services

- **multimodal-ai**: Handles image and voice in conjunction
- **memory-engine**: Stores prompt responses for learning
- **reputation_engine**: Tier-based model access control
- **activity-feed**: Prompt usage events

## Support & Documentation

For additional support, see:

- [LLM Integration Guide](../../COMPLETE_DEPLOYMENT_PROGRAM_SUMMARY.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: ai

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026
