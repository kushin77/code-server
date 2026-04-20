## E2E: Appsmith Portal Feature Testing Suite

### Objective
Create comprehensive E2E test coverage for all Appsmith portal features accessible after OAuth login.

### Current State
- Zero Appsmith feature tests exist
- Tests only cover login redirects, not actual portal functionality
- No validation of Appsmith → IDE integration

### Target Test Matrix (30+ tests)

#### Navigation & Layout (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 1 | `portal-landing-page` | Landing page loads with expected layout |
| 2 | `portal-navigation-menu` | Main navigation menu renders all items |
| 3 | `portal-user-profile` | User profile shows correct email (qa@kushnir.cloud) |
| 4 | `portal-breadcrumbs` | Breadcrumb navigation works correctly |
| 5 | `portal-responsive-mobile` | Mobile layout renders correctly |
| 6 | `portal-dark-mode` | Dark mode toggle works if available |

#### IDE Launch (8 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 7 | `portal-ide-link-visible` | IDE launch link/button is visible |
| 8 | `portal-ide-launch-click` | Click IDE link navigates to ide.kushnir.cloud |
| 9 | `portal-ide-launch-new-tab` | IDE opens in new tab (if configured) |
| 10 | `portal-ide-session-transfer` | OAuth session transfers to IDE subdomain |
| 11 | `portal-ide-back-to-portal` | Can navigate back to portal from IDE |
| 12 | `portal-ide-deep-link` | Direct IDE URL preserves workspace context |
| 13 | `portal-ide-launch-time` | IDE launch completes within 10 seconds |
| 14 | `portal-ide-multiple-launch` | Multiple IDE launches don't create duplicate sessions |

#### Workspace Management (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 15 | `portal-workspace-list` | Workspace list displays all user workspaces |
| 16 | `portal-workspace-create` | Can create new workspace |
| 17 | `portal-workspace-delete` | Can delete workspace |
| 18 | `portal-workspace-rename` | Can rename workspace |
| 19 | `portal-workspace-settings` | Workspace settings accessible |
| 20 | `portal-workspace-share` | Workspace sharing works (if available) |

#### Application Features (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 21 | `portal-app-list` | Application list displays correctly |
| 22 | `portal-app-create` | Can create new application |
| 23 | `portal-app-edit` | Can edit existing application |
| 24 | `portal-app-deploy` | Can deploy application |
| 25 | `portal-app-delete` | Can delete application |
| 26 | `portal-app-preview` | Can preview application |

#### Error & Edge Cases (4 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 27 | `portal-session-timeout` | Expired session redirects to login |
| 28 | `portal-network-error` | Network errors show user-friendly message |
| 29 | `portal-concurrent-edit` | Concurrent edits don't corrupt data |
| 30 | `portal-browser-refresh` | Page refresh preserves state |

### Implementation

**File**: `tests/e2e/specs/appsmith-portal.spec.ts`

```typescript
import { test, expect } from '../fixtures/auth-fixture';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('Appsmith Portal Features', () => {
  // Use authenticated fixture - skips login
  test.use({ storageState: 'tests/e2e/.auth/qa-storage-state.json' });

  test.describe('Navigation & Layout', () => {
    test('landing page loads with expected layout', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Verify main layout elements
      await expect(page.locator('header')).toBeVisible();
      await expect(page.locator('nav')).toBeVisible();
      await expect(page.locator('main')).toBeVisible();
    });

    test('user profile shows correct email', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Click user menu
      await page.click('[data-testid="user-menu"]');
      
      // Verify email
      await expect(page.locator('[data-testid="user-email"]'))
        .toContainText('qa@kushnir.cloud');
    });
  });

  test.describe('IDE Launch', () => {
    test('IDE launch link navigates correctly', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Find and click IDE link
      const ideLink = page.locator('a[href*="ide.kushnir.cloud"]');
      await ideLink.click();
      
      // Verify navigation to IDE
      await page.waitForURL(`${IDE_URL}/**`);
      await expect(page).toHaveURL(new RegExp(IDE_URL.replace('.', '\\.')));
    });

    test('IDE launch completes within 10 seconds', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      const startTime = Date.now();
      await page.click('[data-testid="ide-launch"]');
      await page.waitForURL(`${IDE_URL}/**`);
      const loadTime = Date.now() - startTime;
      
      expect(loadTime).toBeLessThan(10000);
    });
  });

  test.describe('Workspace Management', () => {
    test('workspace list displays correctly', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Verify workspace list is visible
      await expect(page.locator('[data-testid="workspace-list"]')).toBeVisible();
    });
  });
});
```

### Test Data Management

For workspace/application tests, we need test data isolation:

```typescript
// fixtures/test-data.ts
export async function createTestWorkspace(page: Page) {
  const workspaceName = `QA-Test-${Date.now()}`;
  // Create workspace
  return workspaceName;
}

export async function cleanupTestWorkspace(page: Page, workspaceName: string) {
  // Delete workspace after test
}
```

### Selectors Strategy

Appsmith may not have `data-testid` attributes. Fallback strategy:

1. **data-testid** (preferred): `[data-testid="workspace-list"]`
2. **aria-label**: `[aria-label="Launch IDE"]`
3. **class/id** (fragile): `.workspace-container`, `#ide-launch-btn`
4. **text content** (last resort): `text=Launch IDE`

### Definition of Done

- [ ] 30+ Appsmith portal tests implemented
- [ ] Navigation and layout tests pass
- [ ] IDE launch flow fully tested
- [ ] Workspace CRUD operations tested
- [ ] Application CRUD operations tested
- [ ] Error handling verified
- [ ] Tests are stable (no flaky failures)
- [ ] Test data cleanup after each run

Parent: #982
Depends on: #983, #984 (QA account)
Relates to: #986 (OAuth tests complete login, then portal tests take over)
