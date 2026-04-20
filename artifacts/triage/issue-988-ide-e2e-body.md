## E2E: IDE Launch and Workspace Operations

### Objective
Create comprehensive E2E test coverage for code-server IDE functionality accessed via ide.kushnir.cloud.

### Current State
- Zero IDE operation tests exist
- No validation of code-server features post-launch
- Session-broker → code-server flow untested

### Target Test Matrix (25+ tests)

#### IDE Launch & Load (8 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 1 | `ide-launch-success` | IDE loads successfully after auth |
| 2 | `ide-load-time` | IDE fully loads within 15 seconds |
| 3 | `ide-layout-render` | VSCode layout (sidebar, editor, terminal) renders |
| 4 | `ide-welcome-tab` | Welcome tab or last session restores |
| 5 | `ide-menu-bar` | Menu bar (File, Edit, View, etc.) accessible |
| 6 | `ide-activity-bar` | Activity bar (Explorer, Search, Git) functional |
| 7 | `ide-status-bar` | Status bar shows connection status |
| 8 | `ide-command-palette` | Command palette (Ctrl+Shift+P) opens |

#### File Operations (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 9 | `ide-file-create` | Can create new file |
| 10 | `ide-file-edit` | Can edit file content |
| 11 | `ide-file-save` | Can save file (Ctrl+S) |
| 12 | `ide-file-delete` | Can delete file |
| 13 | `ide-folder-create` | Can create new folder |
| 14 | `ide-file-rename` | Can rename file/folder |

#### Terminal Operations (4 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 15 | `ide-terminal-open` | Can open integrated terminal |
| 16 | `ide-terminal-execute` | Can execute commands in terminal |
| 17 | `ide-terminal-output` | Terminal output displays correctly |
| 18 | `ide-terminal-multiple` | Can open multiple terminal tabs |

#### Extension & Features (4 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 19 | `ide-extension-list` | Extension list loads in sidebar |
| 20 | `ide-extension-install` | Can install extension (if allowed) |
| 21 | `ide-git-integration` | Git panel shows repository status |
| 22 | `ide-search-files` | File search (Ctrl+P) works |

#### Session & Persistence (3 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 23 | `ide-session-persist` | Session persists across page refresh |
| 24 | `ide-workspace-restore` | Workspace state restored on reconnect |
| 25 | `ide-logout-cleanup` | Logout cleans up session properly |

### Implementation

**File**: `tests/e2e/specs/ide-operations.spec.ts`

```typescript
import { test, expect } from '../fixtures/auth-fixture';

const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('IDE Operations', () => {
  test.use({ storageState: 'tests/e2e/.auth/qa-storage-state.json' });

  test.describe('IDE Launch & Load', () => {
    test('IDE loads successfully after auth', async ({ page }) => {
      await page.goto(IDE_URL);
      
      // Wait for VSCode to fully load
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Verify main UI elements
      await expect(page.locator('.monaco-workbench')).toBeVisible();
    });

    test('IDE fully loads within 15 seconds', async ({ page }) => {
      const startTime = Date.now();
      await page.goto(IDE_URL);
      
      // Wait for editor to be ready
      await page.waitForSelector('.monaco-editor', { timeout: 15000 });
      const loadTime = Date.now() - startTime;
      
      console.log(`IDE load time: ${loadTime}ms`);
      expect(loadTime).toBeLessThan(15000);
    });

    test('command palette opens', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Open command palette
      await page.keyboard.press('Control+Shift+P');
      
      // Verify command palette is visible
      await expect(page.locator('.quick-input-widget')).toBeVisible();
    });
  });

  test.describe('File Operations', () => {
    test('can create and edit file', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Create new file via command palette
      await page.keyboard.press('Control+Shift+P');
      await page.keyboard.type('New File');
      await page.keyboard.press('Enter');
      
      // Type content
      await page.keyboard.type('// QA Test File\nconsole.log("Hello, QA!");');
      
      // Save file
      await page.keyboard.press('Control+S');
      
      // Handle save dialog
      await page.keyboard.type('qa-test.js');
      await page.keyboard.press('Enter');
      
      // Verify file created
      await expect(page.locator('.explorer-folders-view')).toContainText('qa-test.js');
    });
  });

  test.describe('Terminal Operations', () => {
    test('can open and use terminal', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Open terminal
      await page.keyboard.press('Control+`');
      
      // Verify terminal is visible
      await expect(page.locator('.xterm')).toBeVisible();
      
      // Execute command
      await page.keyboard.type('echo "QA Test"');
      await page.keyboard.press('Enter');
      
      // Verify output
      await expect(page.locator('.xterm')).toContainText('QA Test');
    });
  });

  test.describe('Session Persistence', () => {
    test('session persists across page refresh', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Create a file
      await page.keyboard.press('Control+Shift+P');
      await page.keyboard.type('New File');
      await page.keyboard.press('Enter');
      await page.keyboard.type('// Session test');
      
      // Refresh page
      await page.reload();
      await page.waitForSelector('.monaco-workbench');
      
      // Verify file is still open (or can be recovered)
      // Note: VSCode may prompt to recover unsaved changes
    });
  });
});
```

### VSCode Selector Reference

| Element | Selector |
|---------|----------|
| Workbench | `.monaco-workbench` |
| Editor | `.monaco-editor` |
| Terminal | `.xterm` |
| Sidebar | `.sidebar` |
| Activity Bar | `.activitybar` |
| Status Bar | `.statusbar` |
| Command Palette | `.quick-input-widget` |
| Explorer | `.explorer-folders-view` |

### Test Data Cleanup

After each test run:
```typescript
test.afterEach(async ({ page }) => {
  // Delete test files created during test
  await page.keyboard.press('Control+Shift+P');
  await page.keyboard.type('Delete File');
  await page.keyboard.press('Enter');
  // ... cleanup logic
});
```

### Definition of Done

- [ ] 25+ IDE operation tests implemented
- [ ] IDE launch and load tests pass
- [ ] File operations (CRUD) tested
- [ ] Terminal operations tested
- [ ] Extension/feature tests implemented
- [ ] Session persistence verified
- [ ] Test cleanup removes all test artifacts
- [ ] Tests stable across 10 consecutive runs

Parent: #982
Depends on: #983, #984 (QA account), #987 (portal tests)
