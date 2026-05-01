# Test Plan

**Version**: 2.0  
**Last Updated**: April 24, 2026  
**Audience**: QA Team, Developers, DevOps  

## Overview

This document defines the comprehensive test strategy for the Paperclip platform, covering unit tests, integration tests, end-to-end tests, performance tests, and security tests.

## Testing Strategy

### Test Pyramid

```
        ╱╲
       ╱  ╲         E2E Tests (5%)
      ╱────╲        - User workflows
     ╱      ╲       - Full system validation
    ╱────────╲
   ╱          ╲     Integration Tests (15%)
  ╱────────────╲    - Service contracts
 ╱              ╲   - Database operations
╱────────────────╲  
Unit Tests (80%)
- Functions
- Classes
- Pure logic
```

### Coverage Goals

| Test Type | Target Coverage | Current |
|-----------|-----------------|---------|
| Unit | 80% | 72% |
| Integration | 60% | 55% |
| E2E | 40% | 35% |
| Security | 90% | 85% |

## Unit Tests

### Framework & Tools

- **Framework**: Vitest (JavaScript/TypeScript)
- **Coverage**: nyc (Istanbul)
- **Assertions**: Chai
- **Mocking**: Sinon.js
- **Test Database**: SQLite (in-memory)

### Running Unit Tests

```bash
# Run all unit tests
pnpm test:unit

# Run with coverage report
pnpm test:unit --coverage

# Watch mode (for development)
pnpm test:unit --watch

# Run specific test file
pnpm test:unit src/modules/users/__tests__/user-service.test.ts
```

### Unit Test Structure

```typescript
import { describe, it, beforeEach, expect } from 'vitest';
import { UserService } from '../user-service';
import { UserRepository } from '../user-repository';

describe('UserService', () => {
  let userService: UserService;
  let mockRepository: sinon.SinonSandbox;

  beforeEach(() => {
    mockRepository = sinon.createSandbox();
    userService = new UserService(mockRepository as any);
  });

  describe('createUser', () => {
    it('should create user with valid email', async () => {
      // Arrange
      const userData = { email: 'test@example.com', name: 'Test' };
      mockRepository.stub().returns({ id: '123' });

      // Act
      const result = await userService.createUser(userData);

      // Assert
      expect(result).to.have.property('id');
      expect(result.email).to.equal('test@example.com');
    });

    it('should reject invalid email format', async () => {
      // Arrange
      const userData = { email: 'invalid', name: 'Test' };

      // Act & Assert
      expect(userService.createUser(userData))
        .to.be.rejectedWith('Invalid email format');
    });
  });
});
```

### Coverage Analysis

```bash
# Generate coverage report
pnpm test:unit --coverage --reporters=text-lcov > coverage.lcov

# View HTML report
pnpm test:unit --coverage
# Open: coverage/index.html

# Coverage thresholds (enforced in CI)
{
  "lines": 80,
  "functions": 80,
  "branches": 75,
  "statements": 80
}
```

## Integration Tests

### Framework & Tools

- **Framework**: Vitest + Testcontainers
- **Database**: PostgreSQL (Docker)
- **Cache**: Redis (Docker)
- **Message Queue**: Kafka (Docker)

### Running Integration Tests

```bash
# Start test infrastructure
docker-compose -f docker-compose.test.yml up -d

# Run integration tests
pnpm test:integration

# Run with logs
pnpm test:integration --reporter=verbose

# Stop test infrastructure
docker-compose -f docker-compose.test.yml down
```

### Test Database Setup

```typescript
import { pool } from '@paperclip/db';
import { migrationRunner } from '@paperclip/migrations';

beforeAll(async () => {
  // Run migrations on test database
  await migrationRunner.up();
});

afterAll(async () => {
  // Clean up database connections
  await pool.end();
});

beforeEach(async () => {
  // Clear tables between tests (idempotent)
  await pool.query('TRUNCATE TABLE activities CASCADE');
  await pool.query('TRUNCATE TABLE users CASCADE');
});
```

### Database Contract Tests

```typescript
describe('UserRepository - Database Contract', () => {
  it('should persist user and retrieve by ID', async () => {
    // Arrange
    const user = { email: 'test@example.com', name: 'Test' };

    // Act
    const created = await userRepository.create(user);
    const retrieved = await userRepository.findById(created.id);

    // Assert
    expect(retrieved).to.deep.equal(created);
  });

  it('should enforce unique email constraint', async () => {
    // Arrange
    const email = 'unique@example.com';
    await userRepository.create({ email, name: 'User 1' });

    // Act & Assert
    expect(userRepository.create({ email, name: 'User 2' }))
      .to.be.rejectedWith('Unique violation: email');
  });
});
```

### Service Integration Tests

```typescript
describe('ActivityFeed - Service Integration', () => {
  it('should create activity and emit event', async () => {
    // Arrange
    const kafkaSpy = sinon.spy(kafkaClient, 'produce');

    // Act
    await activityService.logActivity({
      userId: 'user-123',
      action: 'file.created',
      resource: 'file-123'
    });

    // Assert
    expect(kafkaSpy.calledOnce).to.be.true;
    const event = kafkaSpy.getCall(0).args[0];
    expect(event.topic).to.equal('user-activities');
  });
});
```

## End-to-End (E2E) Tests

### Framework & Tools

- **Framework**: Playwright
- **Headless Browser**: Chromium
- **Environment**: Docker Compose (full stack)

### Running E2E Tests

```bash
# Start full stack
docker-compose up -d

# Run E2E tests
pnpm test:e2e

# Run in headed mode (visible browser)
HEADED=true pnpm test:e2e

# Run specific test suite
pnpm test:e2e -- tests/e2e/auth.spec.ts

# Update snapshots (if UI changed intentionally)
pnpm test:e2e -- --update-snapshots
```

### E2E Test Examples

#### Authentication Flow
```typescript
import { test, expect } from '@playwright/test';

test('User authentication flow', async ({ page }) => {
  // Navigate to app
  await page.goto('http://localhost:3000');

  // Click login button
  await page.click('[data-testid="login-button"]');

  // OAuth redirect
  await page.waitForURL('**/github/authorize**');
  
  // GitHub login (mock credentials from test data)
  await page.fill('#login_field', 'test-user');
  await page.fill('#password', 'test-password');
  await page.click('input[type="submit"]');

  // Redirects back to app
  await page.waitForURL('http://localhost:3000/**');

  // Verify logged-in state
  await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
  await expect(page).toHaveURL(/dashboard/);
});
```

#### File Creation Workflow
```typescript
test('Create and edit file', async ({ page }) => {
  // Login first
  await login(page, testUser);

  // Navigate to project
  await page.goto('http://localhost:3000/projects/test-project');

  // Create new file
  await page.click('[data-testid="create-file-button"]');
  await page.fill('input[name="filename"]', 'test.ts');
  await page.click('[data-testid="confirm-button"]');

  // Verify file appears in tree
  await expect(page.locator('text=test.ts')).toBeVisible();

  // Edit file
  await page.click('text=test.ts');
  await page.keyboard.type('console.log("hello");');

  // Save file (Ctrl+S)
  await page.keyboard.press('Control+S');

  // Verify save indication
  await expect(page.locator('[data-testid="save-indicator"]')).toHaveClass(/saved/);
});
```

### Performance Testing

```typescript
test('API response time under load', async ({ page }) => {
  // Perform 100 rapid requests
  const start = Date.now();
  
  for (let i = 0; i < 100; i++) {
    await page.evaluate(() => 
      fetch('/api/activities?limit=10').then(r => r.json())
    );
  }
  
  const duration = Date.now() - start;
  
  // Assert: 100 requests in < 5 seconds (50ms avg)
  expect(duration).toBeLessThan(5000);
});
```

## Performance & Load Testing

### Tools

- **Framework**: Apache JMeter or k6
- **Metrics**: Response time, throughput, resource usage
- **Load Profiles**: Ramp-up, sustained, spike

### Running Performance Tests

```bash
# Install k6
brew install k6

# Run load test
k6 run scripts/load-tests/api-endpoints.js

# Run with custom VU (virtual users) and duration
k6 run -u 50 -d 5m scripts/load-tests/api-endpoints.js
```

### Sample Load Test

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Ramp up
    { duration: '5m', target: 50 },   // Sustain
    { duration: '1m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% < 500ms
    http_req_failed: ['rate<0.1'],     // Error rate < 10%
  },
};

export default function () {
  // Test API endpoint
  const response = http.get('http://localhost:3100/api/activities');
  
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(1);
}
```

### Performance Baselines

| Endpoint | Target | Current | Status |
|----------|--------|---------|--------|
| GET /health | < 50ms | 12ms | ✅ |
| GET /api/activities?limit=10 | < 200ms | 145ms | ✅ |
| POST /api/activities | < 300ms | 280ms | ✅ |
| GET /api/search?q=test | < 500ms | 420ms | ✅ |

## Security Testing

### Tools

- **SAST**: SonarQube
- **DAST**: OWASP ZAP
- **Dependency Scanning**: Snyk, npm audit
- **Container Scanning**: Trivy

### Running Security Tests

```bash
# SonarQube analysis
sonar-scanner \
  -Dsonar.projectKey=code-server \
  -Dsonar.sources=src

# Dependency scanning
npm audit
pnpm audit

# Container image scanning
trivy image code-server:latest

# DAST with ZAP
docker run -u zap -p 8080:8080 \
  -v $(pwd):/zap/wrk:rw \
  ghcr.io/zaproxy/zaproxy:latest \
  zap-baseline.py -t http://localhost:3000
```

### Security Test Cases

#### OWASP Top 10
- [ ] SQL Injection: Parameterized queries, prepared statements
- [ ] Authentication: MFA bypass, token expiration
- [ ] Sensitive Data Exposure: Encryption, HTTPS
- [ ] XXE: Input validation, XML parsers hardened
- [ ] Access Control: RBAC/ABAC enforcement
- [ ] Security Misconfiguration: Default creds, exposed endpoints
- [ ] XSS: Input sanitization, CSP headers
- [ ] Insecure Deserialization: Type validation
- [ ] Using Components with Known Vulnerabilities: Dependency scanning
- [ ] Insufficient Logging: Audit trail completeness

## Continuous Integration Testing

### GitHub Actions Workflow

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3
      
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'pnpm'
      
      # Unit tests
      - run: pnpm test:unit --coverage
      
      # Integration tests
      - run: pnpm test:integration
      
      # E2E tests
      - run: pnpm test:e2e
      
      # Upload coverage
      - uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info
```

## Test Execution Schedule

| Test Type | Frequency | Duration | Trigger |
|-----------|-----------|----------|---------|
| Unit | Every commit | 2 min | Pre-commit, CI |
| Integration | Every commit | 10 min | CI |
| E2E | Every push to main | 30 min | GitHub Actions |
| Performance | Weekly | 1 hour | Scheduled |
| Security | Weekly | 2 hours | Scheduled |
| Penetration | Quarterly | 8 hours | Manual |

## Test Data Management

### Fixtures

```typescript
// tests/fixtures/users.ts
export const testUsers = {
  admin: {
    id: 'user-admin-001',
    email: 'admin@test.local',
    name: 'Admin User',
    role: 'admin',
  },
  collaborator: {
    id: 'user-collab-001',
    email: 'collab@test.local',
    name: 'Collaborator',
    role: 'collaborator',
  },
};

// Usage in tests
beforeEach(async () => {
  await userRepository.create(testUsers.admin);
  await userRepository.create(testUsers.collaborator);
});
```

### Mock Data

```typescript
// Faker for realistic data
import { faker } from '@faker-js/faker';

const mockUser = {
  email: faker.internet.email(),
  name: faker.person.fullName(),
  avatar: faker.image.avatar(),
};
```

## Troubleshooting

### Common Issues

**Test timeout**
```bash
# Increase timeout for slow tests
pnpm test:integration --testTimeout=30000
```

**Database connection errors**
```bash
# Verify test database is running
docker-compose -f docker-compose.test.yml ps

# Reset database
docker-compose -f docker-compose.test.yml down -v
docker-compose -f docker-compose.test.yml up -d
```

**Flaky tests**
```bash
# Run test multiple times to detect flakiness
for i in {1..10}; do pnpm test:unit -- --testNamePattern="Flaky Test"; done
```

## Test Metrics & Reporting

### Coverage Report
- Generated: Every commit
- Threshold: 80% (enforced)
- Trend: Tracked weekly

### Test Results Dashboard
- Dashboard: https://grafana.kushnir.cloud/d/test-results
- Metrics: Pass rate, execution time, coverage trend
- Alerts: Coverage drop > 5%, test failure rate > 10%

## Related Documentation

- [Architecture Overview](../architecture/OVERVIEW.md)
- [Deployment Runbook](../operations/DEPLOYMENT-RUNBOOK.md)
- [Security Guide](../security/SECURITY-GUIDE.md)
