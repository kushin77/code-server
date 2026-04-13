# Testing Configuration and Strategies

## Test Pyramid

```
        △
       /|\
      / | \
     /  |  \  End-to-End Tests (5-10%)
    /   |   \
   /    |    \
  /_____|_____\
  /     |     \
 /      |      \ Integration Tests (15-20%)
/       |       \
/_______|_______\
  /           \
 /             \  Unit Tests (70-80%)
/_____________\
```

## Test Types

### Unit Tests (Jest)
- Test individual functions and components
- Mock external dependencies
- Fast execution (~1-5ms per test)
- Target coverage: 85%

**Files**:
- `extensions/agent-farm/src/**/*.test.ts`

**Command**:
```bash
npm run test:unit -- --coverage
```

**Example**:
```typescript
describe('AuthService', () => {
  it('should authenticate valid user', () => {
    const auth = new AuthService();
    const result = auth.authenticate('user@example.com', 'password');
    expect(result).toEqual({ token: expect.any(String) });
  });

  it('should reject invalid credentials', () => {
    const auth = new AuthService();
    expect(() => auth.authenticate('user', 'wrong')).toThrow();
  });
});
```

### Integration Tests (Jest + Testcontainers)
- Test multiple components together
- Use real services (PostgreSQL, Redis)
- Slower execution (~100-500ms per test)
- Target coverage: 80%

**Files**:
- `extensions/agent-farm/src/**/*.integration.test.ts`

**Command**:
```bash
npm run test:integration -- --coverage
```

**Example**:
```typescript
describe('API Integration', () => {
  let db: PostgresContainer;

  beforeAll(async () => {
    db = await new PostgresContainer().start();
  });

  it('should persist and retrieve user', async () => {
    const user = await db.query('INSERT INTO users ... RETURNING *');
    expect(user.id).toBeDefined();
  });

  afterAll(async () => {
    await db.stop();
  });
});
```

### Security Tests (Custom)
- Test authentication flows
- Validate authorization policies
- Check for vulnerabilities
- Target coverage: Key security paths

**Files**:
- `extensions/agent-farm/src/**/*.security.test.ts`

**Command**:
```bash
npm run test:security
```

**Example**:
```typescript
describe('Security', () => {
  it('should prevent unauthorized access', () => {
    const auth = new AuthService();
    expect(() => auth.verifyToken('invalid-token')).toThrow('Unauthorized');
  });

  it('should enforce RBAC policies', () => {
    const policy = new PolicyEngine();
    const result = policy.evaluate('user', 'read:config');
    expect(result).toBe(false);
  });
});
```

### Performance Tests (Custom Load Testing)
- Measure throughput (requests/second)
- Track latency (p50, p95, p99)
- Monitor memory usage
- Identify bottlenecks

**Files**:
- `extensions/agent-farm/tests/performance/**`

**Command**:
```bash
npm run test:performance
```

**Example**:
```typescript
describe('Performance', () => {
  it('should handle 1000 requests/sec', async () => {
    const loadTest = new LoadTest(1000);
    const results = await loadTest.run(duration: 60s);
    
    expect(results.throughput).toBeGreaterThan(1000);
    expect(results.p99Latency).toBeLessThan(100); // 100ms
  });
});
```

## Coverage Targets

| Metric | Target | Enforcement |
|--------|--------|-------------|
| Statements | 85% | Required |
| Branches | 80% | Required |
| Functions | 85% | Required |
| Lines | 85% | Required |

## Testing Commands

```bash
# Unit tests only
npm run test:unit

# Integration tests only
npm run test:integration

# Security tests only
npm run test:security

# Performance tests only
npm run test:performance

# All tests
npm run test

# With coverage report
npm run test -- --coverage

# Watch mode (development)
npm run test -- --watch

# Specific test file
npm run test -- auth.test.ts

# Update snapshots
npm run test -- -u
```

## Continuous Testing

### Pre-Commit Hooks (Husky)
```bash
# Install husky
npm install husky --save-dev

# Setup hooks
npx husky install

# Pre-commit hook: lint + unit tests
echo "npm run lint && npm run test:unit" > .husky/pre-commit
chmod +x .husky/pre-commit
```

### GitHub Actions
```yaml
on:
  pull_request:
  push:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm ci
      - run: npm run test -- --coverage
      - uses: codecov/codecov-action@v3
```

## Test Data Management

### Fixtures
```typescript
// tests/fixtures/users.ts
export const testUser = {
  id: '1',
  email: 'test@example.com',
  password: 'hashedPassword'
};

export const testUsers = [testUser, ...];
```

### Factories
```typescript
// tests/factories/user-factory.ts
export class UserFactory {
  static create(overrides = {}) {
    return {
      ...testUser,
      ...overrides
    };
  }

  static createMany(count: number) {
    return Array.from({ length: count }, () => this.create());
  }
}
```

### Mocking
```typescript
// Mock external service
jest.mock('../services/external-api', () => ({
  externalApi: {
    call: jest.fn().mockResolvedValue({ data: 'mocked' })
  }
}));
```

## Test Organization

```
extensions/agent-farm/
├── src/
│   ├── auth/
│   │   ├── auth.service.ts
│   │   ├── auth.service.test.ts
│   │   ├── auth.service.integration.test.ts
│   │   └── auth.service.security.test.ts
│   ├── policy/
│   │   ├── policy.engine.ts
│   │   ├── policy.engine.test.ts
│   │   └── policy.engine.security.test.ts
│   └── ...
├── tests/
│   ├── fixtures/
│   │   ├── users.ts
│   │   ├── policies.ts
│   │   └── ...
│   ├── factories/
│   │   ├── user-factory.ts
│   │   └── ...
│   ├── performance/
│   │   ├── auth-perf.test.ts
│   │   └── api-perf.test.ts
│   └── setup.ts
└── jest.config.js
```

## Best Practices

1. **Test Naming**: Use clear, descriptive test names
   ```typescript
   ❌ it('works', () => { ... })
   ✅ it('should return 401 when token is invalid', () => { ... })
   ```

2. **Arrange-Act-Assert Pattern**:
   ```typescript
   it('should authenticate user', () => {
     // Arrange
     const auth = new AuthService();
     const credentials = { email: 'test@example.com', password: 'pass' };
     
     // Act
     const token = auth.authenticate(credentials);
     
     // Assert
     expect(token).toBeDefined();
   });
   ```

3. **One Assertion per Test** (usually):
   ```typescript
   ✅ it('should return user ID', () => {
     const result = getUserById(1);
     expect(result.id).toBe(1);
   });
   
   ✅ it('should return user name', () => {
     const result = getUserById(1);
     expect(result.name).toBe('John');
   });
   ```

4. **Use Descriptive Variable Names**:
   ```typescript
   ❌ const a = auth.verify(t);
   ✅ const isTokenValid = authService.verifyToken(token);
   ```

5. **Mock External Dependencies**:
   ```typescript
   const mockDatabase = jest.fn();
   mockDatabase.mockResolvedValue({ id: 1 });
   
   const user = await getUserFromDb(1);
   expect(user.id).toBe(1);
   ```

## Debugging Tests

```bash
# Run single test
npm run test -- auth.service.test.ts

# Run tests matching pattern
npm run test -- --testNamePattern="authenticate"

# Debug with Node inspector
node --inspect-brk node_modules/.bin/jest

# Verbose output
npm run test -- --verbose

# Show coverage details
npm run test -- --coverage --coverageReporters=text-summary
```

## Performance Targets

| Metric | Target | SLA |
|--------|--------|-----|
| Auth latency (p99) | < 100ms | 99.5% |
| Policy eval (p99) | < 50ms | 99.5% |
| Threat detection (p99) | < 500ms | 98% |
| API throughput | > 1000 RPS | 99% |

## Integration with CI/CD

Tests run on:
- ✓ Pull requests (block on failure)
- ✓ Develop branch (staging deployment gate)
- ✓ Main branch (production deployment gate)
- ✓ Schedule (nightly comprehensive suite)

---

**Status**: Ready for Implementation  
**Last Updated**: 2024-01-27  
**Version**: 1.0.0
