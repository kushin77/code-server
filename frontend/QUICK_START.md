# Quick Start Guide - RBAC Frontend Development

**For**: New developers joining the project  
**Time**: 5-10 minutes  
**Version**: 1.0.0

---

## Prerequisites

Verify you have:
- Node.js 18+ (`node --version`)
- npm 9+ (`npm --version`)
- Git (`git --version`)
- Text editor / IDE (VS Code recommended)

## Setup (5 minutes)

### Step 1: Install Dependencies

```bash
cd frontend
npm install
```

Expected output:
```
added 500 packages in 15s
```

### Step 2: Start Development Server

```bash
npm run dev
```

Expected output:
```
VITE v5.0.8  ready in 245 ms

➜  Local:   http://localhost:3000/
```

### Step 3: Open in Browser

Visit `http://localhost:3000`

You should see:
- Login page with email/password fields
- "🔐 RBAC Dashboard" branding

## Verify Backend Connection

Backend API should be running on `http://localhost:3001`

```bash
curl http://localhost:3001/health
# Expected: { "status": "ok" }
```

If you see 404 or connection refused:
- Start backend API: `cd services/rbac-api && npm run dev`
- Check port 3001 is available

## Try Features

### 1. Explore Components

Open `frontend/src/components/Common.tsx` to see all UI components.

Try in browser console:
```javascript
// Inspect the page structure
console.log(document.querySelector('button'))
```

### 2. Try Login Page

Click username/password fields:
- Email: `admin@example.com` (demo, won't work yet)
- You'll see form validation

### 3. Check Network Requests

Open Browser DevTools (F12):
- Go to Network tab
- Try to login
- See API request to `http://localhost:3001/auth/login`

## Project Structure

```
frontend/
├── src/
│   ├── components/      # UI components (Button, Modal, etc)
│   ├── pages/          # Full pages (UserManagementPage)
│   ├── hooks/          # Custom React hooks (useLogin, etc)
│   ├── api/            # RBAC API client (rbacAPI)
│   ├── store/          # Zustand stores (auth, user, role)
│   ├── types/          # TypeScript interfaces
│   ├── App.tsx         # Router + layout
│   ├── main.tsx        # Entry point
│   └── index.css       # Global styles
│
├── README.md           # Full documentation
├── ARCHITECTURE.md     # Design decisions
├── API.md             # API endpoint reference
├── DEPLOYMENT.md      # Deploy instructions
└── package.json       # Dependencies
```

## Common Tasks

### Modify a Component

Example: Change button text in Login page

```bash
# 1. Open file
code src/pages/UserManagement.tsx

# 2. Find the button
<Button label="New User" ... />

# 3. Change text
<Button label="Create User" ... />

# 4. Browser updates automatically (HMR)
```

### Add New API Method

Example: Add `getOrgDetails()` method

```typescript
// In frontend/src/api/rbac-client.ts

async getOrgDetails(orgId: string): Promise<Organization> {
  return this.get(`/admin/orgs/${orgId}`)
}

// In frontend/src/types/index.ts
interface Organization {
  id: string
  slug: string
  name: string
}

// Use in hook
const { org } = await rbacAPI.getOrgDetails(orgId)
```

### Create New Page

Example: Add Repository Access page

```bash
# 1. Create file
code src/pages/RepositoryAccess.tsx

# 2. Add component
export const RepositoryAccessPage: React.FC = () => {
  return <div>Repository Access</div>
}

# 3. Add to router in App.tsx
<Route path="/repos" element={<RepositoryAccessPage />} />

# 4. Browser: http://localhost:3000/repos
```

### Run Tests

```bash
npm run test           # Run all tests once
npm run test:watch    # Watch mode (restart on changes)
npm run coverage      # Coverage report
```

### Build for Production

```bash
npm run build
npm run preview       # Preview production build
```

## Common Issues

### Issue: "Cannot GET /" on page refresh

**Cause**: Vite dev server not configured for SPA

**Fix**: Should be pre-configured. If not:
```bash
npm run dev
# And access only through http://localhost:3000
# Not by opening index.html directly
```

### Issue: "VITE_API_URL is not defined"

**Cause**: Environment variables not loaded

**Fix**: Restart dev server
```bash
npm run dev
```

### Issue: Port 3000 already in use

**Cause**: Another app using port 3000

**Fix**: 
```bash
# Kill process on port 3000
lsof -ti:3000 | xargs kill -9

# Or use different port
npm run dev -- --port 3001
```

### Issue: Module not found errors

**Cause**: Dependencies not installed

**Fix**:
```bash
rm -rf node_modules
npm install
npm run dev
```

## Development Tips

### 1. Use TypeScript Strict Mode

All code is in strict TypeScript. This catches errors at compile-time:
```typescript
// ✅ Good - TypeScript knows type
const user: User = { id: '1', email: 'test@example.com' }

// ❌ Bad - Type error
const user: User = { id: 1 } // Type 'number' is not assignable to 'string'
```

### 2. Use VSCode Extensions

Recommended:
- **ES7+ React/Redux/React-Native snippets** (dsznajder.es7-react-js-snippets)
- **Tailwind CSS IntelliSense** (bradlc.vscode-tailwindcss)
- **Prettier** (esbenp.prettier-vscode)

### 3. Format Code

```bash
npm run format  # Auto-format with Prettier
npm run lint    # Check for issues
```

### 4. Debug in Browser

```bash
// In any component
console.log('Current user:', useAuthStore.getState().user)
console.log('Is loading:', useAuthStore.getState().isLoading)

// Inspect Zustand store
window.__ZUSTAND_DEVTOOLS_EXTENSION__?.()
```

### 5. Check Bundle Size

```bash
npm run build -- --analyze
# Shows what's in the bundle
```

## Next Steps

1. **Understand Architecture**: Read [ARCHITECTURE.md](./ARCHITECTURE.md)
2. **Learn API**: Read [API.md](./API.md)
3. **First Task**: Pick a component to modify or enhance
4. **Ask Questions**: Check documentation or ask team lead

## Documentation

- **Full Guide**: [README.md](./README.md)
- **Architecture**: [ARCHITECTURE.md](./ARCHITECTURE.md)
- **API Reference**: [API.md](./API.md)
- **Deployment**: [DEPLOYMENT.md](./DEPLOYMENT.md)

## Useful Commands Reference

```bash
npm run dev           # Start development server (http://localhost:3000)
npm run build         # Create production build
npm run preview       # Preview production build
npm run test          # Run tests
npm run test:watch    # Watch mode
npm run coverage      # Test coverage
npm run type-check    # Check TypeScript
npm run lint          # Check code quality
npm run format        # Format code with Prettier
```

## Keyboard Shortcuts (VS Code)

```
Ctrl+Shift+F  - Format document
Ctrl+Shift+P  - Command palette (npm scripts)
Ctrl+/        - Toggle comment
Alt+Up/Down   - Move line
F12           - Open DevTools
```

## Git Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes
git add .

# Commit
git commit -m "feat: add new feature"

# Push
git push origin feature/my-feature

# Create PR (GitHub UI)
```

## Support

- **Error in npm install?** Check Node.js version: `node --version` should be 18+
- **API not connecting?** Check backend is running: `curl http://localhost:3001/health`
- **Styles not loading?** Restart dev server: `npm run dev`
- **Still stuck?** Ask in #dev-frontend Slack channel

---

**Welcome to RBAC Frontend! 🚀**

**Time to productivity**: 5-10 minutes  
**Next**: Clone repo → npm install → npm run dev → read docs
