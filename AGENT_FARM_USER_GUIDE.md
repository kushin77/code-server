# Agent Farm MVP - User Guide & Quick Reference

**Version**: 1.0 (Phase 1 MVP)  
**Updated**: April 12, 2026  
**Status**: Ready for Production  

---

## What is Agent Farm?

Agent Farm is a multi-agent development system built into your code-server IDE that provides intelligent code analysis from multiple specialized perspectives. Each agent is an expert in a specific domain:

- **CodeAgent** 🔧: Implementation specialist - analyzes code quality, performance, best practices
- **ReviewAgent** 🔍: Security auditor - checks code quality, security, and compliance

Agents run independently and their findings are combined for comprehensive analysis.

---

## Quick Start (30 seconds)

### 1. Open a Code File
```
Click on any file in your workspace (TypeScript, JavaScript, Python, etc.)
```

### 2. Run Agent Farm
```
Ctrl+Shift+P (Windows/Linux) or Cmd+Shift+P (Mac)
Type: "Agent Farm: Analyze File"
Press Enter
```

### 3. View Results
```
Results appear in the Agent Farm Dashboard
Recommendations sorted by severity (Critical → Warning → Info)
```

That's it! ✨

---

## Commands Reference

### Primary Commands

| Command | Shortcut | Purpose |
|---------|----------|---------|
| **Analyze File** | `agentFarm.analyzeFile` | Run full analysis on current file |
| **Quick Analysis** | `agentFarm.analyzeWithTask` | Choose specific analysis type |
| **Show Dashboard** | `agentFarm.showDashboard` | Open results dashboard |
| **Index File** | `agentFarm.indexFile` | See code metrics and structure |

### Management Commands

| Command | Purpose |
|---------|---------|
| `agentFarm.listAgents` | Show available agents |
| `agentFarm.showAuditTrail` | View analysis history |
| `agentFarm.clearAuditTrail` | Clear stored results |

---

## Analysis Modes

### Full Analysis (Recommended)
```
Runs ALL available agents on the file
⏱️ Time: 2-5 seconds per file
✅ Best for: First-time analysis, comprehensive review
```

**What you get**:
- CodeAgent: Implementation issues (8 checks)
- ReviewAgent: Security & quality issues (10 checks)
- Combined findings sorted by severity

### Quick Analysis
```
Run only selected analysis types
⏱️ Time: <1 second
✅ Best for: Specific issues you're targeting
```

**Options**:
- Code Quality Review
- Security Scan
- Performance Check
- Best Practices

---

## Understanding the Dashboard

### Layout
```
┌─────────────────────────────────────────────────────┐
│           Agent Farm Analysis Results                │
├─────────────────────────────────────────────────────┤
│                                                      │
│  📊 Summary                                          │
│  ├─ CRITICAL: 2                                      │
│  ├─ WARNING: 5                                       │
│  └─ INFO: 3                                          │
│                                                      │
│  🔧 CodeAgent Results                               │
│  ├─ ❌ CRITICAL: Magic number detected (line 45)   │
│  ├─ ⚠️  WARNING: Long function (58 lines)           │
│  └─ ℹ️  INFO: Consider async/await (line 23)        │
│                                                      │
│  🔍 ReviewAgent Results                             │
│  ├─ ❌ CRITICAL: Hardcoded credential (line 12)    │
│  └─ ⚠️  WARNING: Missing documentation              │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Result Cards

Each finding includes:

**Header**:
- Severity (CRITICAL 🔴 | WARNING 🟡 | INFO 🔵)
- Issue type
- Location (file:line)

**Body**:
- What the problem is
- Why it matters
- Suggested fix

**Footer**:
- "View Code" button
- "Implement" button (when applicable)

---

## CodeAgent: What It Checks

### 🔧 Implementation Quality

#### 1. Missing Error Handling
```javascript
// ❌ Problem
const response = await fetch(url)
const data = response.json()  // No error handling!

// ✅ Suggested Fix
try {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`HTTP ${response.status}`)
  const data = await response.json()
} catch (error) {
  console.error('Failed to fetch:', error)
  // Handle error appropriately
}
```

#### 2. Console.log Statements
```javascript
// ❌ Problem
console.log('Debug message')  // Forgot to remove!

// ✅ Suggested Fix
import logger from './logger'
logger.debug('Debug message')  // Use proper logging
```

#### 3. Magic Numbers
```javascript
// ❌ Problem
if (age > 18 && status !== null) {  // What's 18?
  
// ✅ Suggested Fix
const ADULT_AGE = 18
if (age > ADULT_AGE && status !== null) {
```

#### 4. Code Duplication
```javascript
// ❌ Problem - Same logic in 3 places
function validateEmail() { /* ... */ }
function validatePhone() { /* ... */ }
function validateAddress() { /* ... */ }

// ✅ Suggested Fix
function validateField(value, rules) { /* ... */ }
```

#### 5. Long Functions
```javascript
// ❌ Problem
function processOrder() {
  // 80+ lines of code in one function!
  // Hard to test, hard to understand
}

// ✅ Suggested Fix - Break into smaller functions
function processOrder() {
  validateOrder(order)
  calculateShipping(order)
  applyDiscounts(order)
  saveToDatabase(order)
}
```

#### 6. Nested Loops (O(n²) Complexity)
```javascript
// ❌ Problem - O(n²) nested loops
for (const user of users) {
  for (const order of orders) {
    if (user.id === order.userId) {
      // This is inefficient!
    }
  }
}

// ✅ Suggested Fix - Create lookup map O(n)
const userOrders = new Map()
for (const order of orders) {
  userOrders.set(order.userId, order)
}
```

#### 7. Synchronous File Operations
```javascript
// ❌ Problem - Blocks event loop
const data = fs.readFileSync('./config.json')

// ✅ Suggested Fix - Use async/await
const data = await fs.promises.readFile('./config.json')
```

#### 8. Expensive Recursion
```javascript
// ❌ Problem - O(2^n) - exponential!
function fibonacci(n) {
  if (n <= 1) return n
  return fibonacci(n-1) + fibonacci(n-2)  // Recalculates same values
}

// ✅ Suggested Fix - Add memoization
const memo = new Map()
function fibonacci(n) {
  if (memo.has(n)) return memo.get(n)
  const result = n <= 1 ? n : fibonacci(n-1) + fibonacci(n-2)
  memo.set(n, result)
  return result
}
```

---

## ReviewAgent: What It Checks

### 🔍 Code Review & Security

#### 1. Inconsistent Naming Conventions
```javascript
// ❌ Problem - Mixed naming styles
const userName = ''      // camelCase
const user_email = ''    // snake_case
const UserAge = 0        // PascalCase for variable

// ✅ Suggested Fix - Be consistent
const userName = ''
const userEmail = ''
const userAge = 0
```

#### 2. Insufficient Documentation
```javascript
// ❌ Problem - No documentation
function calculate(x, y, z) {
  return (x * y) / z
}

// ✅ Suggested Fix - Add clear documentation
/**
 * Calculate the weighted average of three values.
 * 
 * @param {number} x - First value
 * @param {number} y - Weight multiplier
 * @param {number} z - Division factor
 * @returns {number} The weighted average
 * @throws {Error} If z is zero
 */
function calculate(x, y, z) {
  if (z === 0) throw new Error('Division by zero')
  return (x * y) / z
}
```

#### 3. Unresolved TODO/FIXME Comments
```javascript
// ❌ Problem - TODO left in production code
// TODO: Add proper error handling
// FIXME: This is a temporary workaround

if (/* condition */) {
  // ...
}

// ✅ Solution - Either fix it or track in issues
// Create GitHub issue with details
// Remove comment after fix
if (/* condition */) {
  // ...
}
```

#### 4. ⚠️ CRITICAL: Hardcoded Credentials
```javascript
// ❌ CRITICAL SECURITY ISSUE
const apiKey = 'sk_live_1234567890abcdef'
const password = 'MyPassword123'
const databaseUrl = 'postgres://user:pass@host'

// ✅ Suggested Fix - Use environment variables
const apiKey = process.env.API_KEY
const password = process.env.PASSWORD
const databaseUrl = process.env.DATABASE_URL
```

#### 5. SQL Injection Vulnerabilities
```javascript
// ❌ CRITICAL - SQL Injection risk
const query = `SELECT * FROM users WHERE id = ${userId}`
db.query(query)

// ✅ Suggested Fix - Use parameterized queries
const query = 'SELECT * FROM users WHERE id = $1'
db.query(query, [userId])  // ID is safely parameterized
```

#### 6. eval() Usage
```javascript
// ❌ CRITICAL - Never use eval
const userInput = getUserInput()
eval(userInput)  // Arbitrary code execution!

// ✅ Suggested Fix - Use JSON.parse or safe alternatives
const userInput = getUserInput()
const data = JSON.parse(userInput)  // Safe parsing
```

#### 7. RegEx Denial of Service (ReDoS)
```javascript
// ❌ Problem - Can cause catastrophic backtracking
const regex = /^(a+)+$/  // Nested quantifiers!

// ✅ Suggested Fix - Simplify regex
const regex = /^a+$/  // Simple alternation
```

#### 8. Loose Equality Checks
```javascript
// ❌ Problem - == is unpredictable
if (value == null) { }       // Matches null AND undefined
if (status == 0 ) { }        // Might match 'false' too!

// ✅ Suggested Fix - Use strict equality
if (value === null) { }      // Only null
if (status === 0) { }        // Only 0
if (value == null) { }       // OK only if you mean null|undefined
```

#### 9. Vague Error Messages
```javascript
// ❌ Problem - What went wrong?
throw new Error('Error')

// ✅ Suggested Fix - Be specific
throw new Error('Failed to connect to database: timeout after 30s')
throw new Error(`Invalid user ID: ${userId} must be a positive integer`)
```

#### 10. Module System Mix
```javascript
// ❌ Problem - Mixing CommonJS and ES6
const express = require('express')  // CommonJS
export function handler() { }       // ES6 export

// ✅ Suggested Fix - Pick one
// Option 1: All CommonJS
const express = require('express')
module.exports = { handler }

// Option 2: All ES6
import express from 'express'
export function handler() { }
```

---

## Using Findings

### View Detailed Code
Click "View Code" to jump directly to the issue in your editor:

```
Dashboard Result:
  ❌ CRITICAL: Hardcoded password (line 42)
  
Click → Editor jumps to line 42
        Issue highlighted
        Agent suggests fix
```

### Implement Suggestions

**Option 1: One-Click Apply**
```
Click "Implement" button
Agent inserts suggested code
You review and commit
```

**Option 2: Manual Implementation**
```
Read "Suggested Fix" in dashboard
Manually implement in editor
This is recommended for learning
```

**Option 3: Defer Assessment**
```
Not all suggestions are urgent
Mark for later with "Defer" button
Review audit trail to track findings
```

---

## Best Practices

### 1. Run Regularly
```
✅ Run on new files immediately
✅ Run before committing to main
✅ Run as part of code review
✅ Run during refactoring
```

### 2. Start with Critical Issues
```
🔴 CRITICAL issues (security, crashes) - Fix immediately
🟡 WARNING issues (quality, performance) - Fix soon
🔵 INFO issues (suggestions, patterns) - Fix eventually
```

### 3. Understand Before Implementing
```
Read the explanation, not just the code suggestion
Understand WHY it's an issue
Make sure the suggestion fits your context
```

### 4. Track Implementation
```
The Audit Trail tracks:
  ✓ When findings were discovered
  ✓ Which findings you implemented
  ✓ Which findings you deferred
  
This helps track your team's progress!
```

### 5. Use in Code Review
```
Include Agent Farm results in PR review:

"Agent Farm found 2 critical security issues:
 1. Line 45: Hardcoded API key → Move to .env
 2. Line 67: SQL injection risk → Use parameterized query

Let me fix these and push again."
```

---

## Performance Tips

### Large Files
If a file is very large (>1000 lines):
- Agent Farm can still analyze it
- It might take 5-10 seconds
- Consider breaking into smaller files

### Slow Analysis
If analysis seems slow:
1. Check file size
2. Check if Ollama is running (needed for semantic features)
3. Try "Quick Analysis" instead of full analysis

### Results Storage
Agent Farm stores results in memory:
- Results are cleared when you close the IDE
- Large histories might slow down UI
- Use "Clear Audit Trail" to free memory

---

## Troubleshooting

### "Analyze File" button doesn't work
**Solution**: 
- Open VS Code command palette (Ctrl+Shift+P)
- Type "Reload Window"
- Try again

### No results appear
**Solution**:
- Verify the file is a supported language (JavaScript, TypeScript, Python, etc.)
- Check browser console for errors (F12)
- Ensure extension is installed and enabled

### Results look wrong
**Solution**:
- Agents are not perfect (they're AI-assisted)
- Always review suggestions carefully
- Report issues to help improve agents

### "Cannot connect to Ollama"
**Solution**:
- Some features need Ollama running
- Run: `docker compose up -d ollama`
- Wait 10 seconds for startup
- Retry analysis

---

## Integration with Development Workflow

### Before Commit
```bash
git add .
# Run Agent Farm on modified files
git commit -m "Fix: Address Agent Farm findings"
git push
```

### In Code Review
```
See Agent Farm dashboard in team reviews:
- Share results in PR comments
- Discuss findings together
- Agree on implementation approach
- Track as PR requirement
```

### In Pre-Commit Hook (coming in Phase 2)
```bash
# .git/hooks/pre-commit
code-server-agent run --fail-on-critical
# Blocks commit if critical issues found
```

---

## Privacy & Data

### What Agent Farm Analyzes
✅ Only the files/code you tell it to analyze  
✅ Analysis runs locally (no external servers)  
✅ Results stored in IDE session only  

### What Agent Farm Does NOT Do
❌ doesn't upload code to external services  
❌ doesn't share findings with anyone  
❌ doesn't modify your code without approval  

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Command Palette | `Ctrl+Shift+P` |
| Quick Analyze | (configure in settings) |
| Focus Dashboard | (configure in settings) |
| Close Dashboard | `Escape` |

---

## Tips & Tricks

### Analyze Multiple Files
```
1. Run analysis on File A
2. Note findings
3. Open File B
4. Run analysis on File B
5. Check "Show Audit Trail" to see both
```

### Find Patterns
```
If reviewing similar files:
1. Analyze file-a.ts → See findings
2. Analyze file-b.ts → Compare findings
3. Notice patterns across files
4. Fix systematically
```

### Team Metrics
```
Track over time:
- How many critical issues do we find?
- How many do we fix?
- Are we implementing more suggestions?
- Is code quality improving?

Share metrics with team! 📊
```

---

## Getting Help

### In-IDE Help
- Right-click any issue → "Explain This"
- Each finding links to detailed docs
- Hover over terms for tooltips

### Documentation
- [IMPLEMENTATION.md](./extensions/agent-farm/IMPLEMENTATION.md) - Technical details
- [QUICK_START.md](./extensions/agent-farm/QUICK_START_MD) - Setup guide
- This guide - Usage reference

### Feedback
Report issues or suggestions:
```
GitHub Issues: https://github.com/kushin77/code-server/issues/80
Include:
- What you were analyzing
- What you expected
- What actually happened
- Screenshots if possible
```

---

## Next Steps

### Learn More
✅ Read the example findings above  
✅ Run analysis on your code  
✅ Implement one critical finding  
✅ Check audit trail  
✅ Celebrate your improvement! 🎉  

### Phase 2 Coming Soon
- ✨ ArchitectAgent (design analysis)
- ✨ TestAgent (coverage analysis)  
- ✨ Semantic code search
- ✨ Team metrics dashboard

---

## FAQ

**Q: Can Agent Farm fix code automatically?**  
A: No, it finds issues and suggests fixes. You control what gets implemented.

**Q: Will it replace code review?**  
A: No, it supplements human review. Humans still make final decisions.

**Q: Is my code secure?**  
A: Yes, analysis runs locally. Code never leaves your machine.

**Q: Why did it miss something?**  
A: Agents are AI-assisted and have limits. Report to help improve.

**Q: Can I disable specific checks?**  
A: Partially now, fully customizable in Phase 2.

---

## Summary

| Feature | MVP (Phase 1) | Phase 2 | Phase 3 |
|---------||----|
| CodeAgent | ✅ | ✅ | ✅ |
| ReviewAgent | ✅ | ✅ | ✅ |
| ArchitectAgent | ⏳ | ✅ | ✅ |
| TestAgent | ⏳ | ✅ | ✅ |
| Semantic Search | ⏳ | ✅ | ✅ |
| CI/CD Integration | ⏳ | ✅ | ✅ |
| Team Analytics | ⏳ | ✅ | ✅ |

---

**Version**: 1.0 MVP  
**Last Updated**: April 12, 2026  
**Status**: Ready for Production Use  

Happy analyzing! 🚀

