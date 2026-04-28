# IDE Extension Service

Core IDE integration and plugin system for Code Server Enterprise. Bridges web IDE and desktop clients with shared extension runtime and feature parity.

## Architecture Overview

IDE Extension Service provides:

- **IDE Runtime**: Unified runtime for web and desktop IDE environments
- **Feature Parity**: Ensures web and desktop have equivalent capabilities
- **Hot Reload**: Reload extensions without restarting IDE
- **WebSocket Communication**: Real-time bidirectional IDE ↔ extension communication
- **Theme Management**: Synchronized theme settings across clients
- **Keybinding Resolution**: Cross-platform key binding normalization
- **Performance**: Optimized extension loading and caching

## Core Components

### 1. IDE Runtime

```python
# Example: Initialize IDE extension runtime
POST /runtime/init
{
    "client_type": "web|desktop",
    "client_version": "3.0.1",
    "os": "linux|macos|windows",
    "extensions": [
        {
            "id": "ext-001",
            "version": "1.0.0"
        }
    ]
}

Response:
{
    "runtime_id": "rt-001",
    "client_type": "web",
    "features": ["hot_reload", "websocket"],
    "extensions_loaded": 15,
    "ready": true
}
```

### 2. Extension Host

```python
# Example: Load extension in IDE runtime
POST /runtime/{runtime_id}/extensions/load
{
    "extension_id": "ext-001",
    "version": "1.0.0"
}

Response:
{
    "extension_id": "ext-001",
    "status": "loaded",
    "activation_time_ms": 234,
    "provides": ["commands", "keybindings", "snippets"]
}
```

### 3. WebSocket Communication

```python
# WebSocket connection for real-time IDE-extension communication
ws://ide-extension:8017/ws/runtime/{runtime_id}

# Extension requests access
{
    "type": "request",
    "id": "req-001",
    "extension": "ext-001",
    "method": "getWorkspaceFolder"
}

# IDE responds
{
    "type": "response",
    "id": "req-001",
    "result": {
        "uri": "file:///workspace/project",
        "name": "project",
        "index": 0
    }
}
```

### 4. Theme Manager

```python
# Example: Set theme and keybindings
POST /themes/apply
{
    "theme_id": "dark-pro",
    "keybinding_set": "vim",
    "font_family": "Fira Code",
    "font_size": 14
}

Response:
{
    "theme": "dark-pro",
    "keybindings": "vim",
    "applied_to_clients": 8
}
```

## API Endpoints

### Runtime Management

```bash
# Initialize IDE runtime
POST /runtime/init
{...}

# Get runtime status
GET /runtime/{runtime_id}

# Dispose runtime (shutdown)
DELETE /runtime/{runtime_id}

# Get runtime metrics
GET /runtime/{runtime_id}/metrics
```

### Extension Loading

```bash
# Load extension
POST /runtime/{runtime_id}/extensions/load
{...}

# Unload extension
POST /runtime/{runtime_id}/extensions/unload
{...}

# Hot reload extension
POST /runtime/{runtime_id}/extensions/{ext_id}/reload

# Get loaded extensions
GET /runtime/{runtime_id}/extensions
```

### Commands & Keybindings

```bash
# Execute command
POST /runtime/{runtime_id}/commands/execute
{
    "command": "editor.action.formatDocument"
}

# Get available commands
GET /runtime/{runtime_id}/commands

# Get keybindings
GET /runtime/{runtime_id}/keybindings

# Set keybindings
PUT /runtime/{runtime_id}/keybindings
{
    "keybinding_set": "vim|emacs|default"
}
```

### Theme Management

```bash
# Get available themes
GET /themes

# Apply theme
POST /themes/apply
{...}

# Get current theme
GET /themes/current
```

## Configuration

### Environment Variables

```bash
# IDE Runtime Configuration
IDE_EXTENSION_RUNTIME_POOL_SIZE=100
IDE_EXTENSION_ENABLE_HOT_RELOAD=true
IDE_EXTENSION_ENABLE_WEBSOCKET=true

# Performance
IDE_EXTENSION_MAX_STARTUP_TIME_MS=5000
IDE_EXTENSION_EXTENSION_HOST_TIMEOUT_MS=30000

# Web IDE
IDE_EXTENSION_WEB_HOST=0.0.0.0
IDE_EXTENSION_WEB_PORT=8017

# Features
IDE_EXTENSION_ENABLE_DEBUG_MODE=false
IDE_EXTENSION_ENABLE_PROFILING=false
```

### Docker Compose Configuration

```yaml
ide-extension:
  image: kushin77/code-server-ide-extension@sha256:xyz789...
  ports:
    - "8017:8000"
  environment:
    - IDE_EXTENSION_RUNTIME_POOL_SIZE=100
    - IDE_EXTENSION_ENABLE_HOT_RELOAD=true
  depends_on:
    - extensions
  volumes:
    - /var/lib/ide-extension:/var/lib/ide-extension
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
```

## IDE Commands

### Text Editor Commands

```
editor.action.formatDocument
editor.action.formatSelection
editor.action.revealDefinition
editor.action.rename
editor.action.goToTypeDefinition
editor.action.implementationProvider
editor.action.quickFix
```

### File Commands

```
file.newUntitledFile
file.open
file.save
file.saveAs
file.close
file.closeAll
file.delete
file.rename
```

### Search Commands

```
search.action.openNewEditor
search.action.replace
search.action.replaceAll
search.action.replaceInFile
search.action.openNewEditorToSide
```

### Debug Commands

```
debug.start
debug.pause
debug.continue
debug.stepOver
debug.stepInto
debug.stepOut
debug.stop
```

## IDE Keybinding Sets

### Vim Keybindings

```
j/k         - Move down/up
h/l         - Move left/right
dd          - Delete line
yy          - Copy line
p/P         - Paste after/before
/           - Search forward
?           - Search backward
:w          - Save
:q          - Quit
```

### Emacs Keybindings

```
Ctrl-A      - Beginning of line
Ctrl-E      - End of line
Ctrl-K      - Kill line
Ctrl-Y      - Yank (paste)
Ctrl-X Ctrl-S - Save
Ctrl-X Ctrl-C - Quit
Meta-X      - Command palette
```

### VS Code Keybindings (Default)

```
Ctrl-P         - Quick file open
Ctrl-Shift-F   - Find in files
Ctrl-F         - Find
Ctrl-H         - Replace
Ctrl-G         - Go to line
F12            - Go to definition
Ctrl-K Ctrl-X  - Close editor
```

## Hot Reload

### Extension Development

```python
# Extension sends reload request
POST /runtime/{runtime_id}/extensions/{ext_id}/reload

# IDE reloads extension without restart
# Maintains editor state and open files
# Reconnects WebSocket communication
```

### Watch Mode

```bash
# Enable watch mode for development
IDE_EXTENSION_WATCH_MODE=true
IDE_EXTENSION_WATCH_PATHS=/var/lib/extensions/**/*.ts
```

## WebSocket Protocol

### Connection Flow

```
Client → Server: Connect to ws://host/ws/runtime/{runtime_id}
Server → Client: { "type": "connected", "runtime_id": "rt-001" }

Client → Server: { "type": "request", "method": "...", "params": {...} }
Server → Client: { "type": "response", "result": {...} }

Client → Server: { "type": "notification", "method": "..." }
```

### Example Messages

```json
// Request from extension to IDE
{
    "type": "request",
    "id": "req-123",
    "extension": "ext-001",
    "method": "workspace.openTextDocument",
    "params": {
        "uri": "file:///workspace/file.ts"
    }
}

// Response from IDE to extension
{
    "type": "response",
    "id": "req-123",
    "result": {
        "uri": "file:///workspace/file.ts",
        "content": "...",
        "languageId": "typescript"
    }
}

// Notification from extension
{
    "type": "notification",
    "extension": "ext-001",
    "method": "statusBar.setMessage",
    "params": {
        "message": "Extension ready"
    }
}
```

## Performance Optimization

### Extension Caching

- Cache compiled extensions in `/var/lib/ide-extension/cache`
- Versioned cache entries for fast startup
- Lazy load non-critical extensions

### Memory Management

- Dispose unused runtimes after 30 minutes idle
- Unload extensions not used in last hour
- Aggressive garbage collection for web IDE

### Connection Pooling

- Maintain pool of 100 runtime instances
- Reuse runtimes for new connections
- Preload common extensions

## Monitoring & Observability

### Key Metrics

```
ide_extension_runtime_count
ide_extension_active_runtimes
ide_extension_startup_time_ms
ide_extension_memory_usage_mb
ide_extension_command_execution_time_ms
ide_extension_extension_load_time_ms
ide_extension_websocket_message_latency_ms
```

## Production Deployment Checklist

- [ ] Multiple IDE runtime instances (10+ min)
- [ ] Extension cache storage provisioned
- [ ] WebSocket server configured
- [ ] Performance monitoring enabled
- [ ] Hot reload functionality tested
- [ ] Theme engine operational
- [ ] Keybinding sets configured
- [ ] Extension compatibility verified
- [ ] Monitoring and alerting configured

## Related Services

- **extensions**: Extension registry and management
- **auth-server**: IDE user authentication
- **activity-feed**: IDE activity events

## Support & Documentation

For additional support, see:

- [IDE Architecture Guide](../../COMPLETE_DEPLOYMENT_PROGRAM_SUMMARY.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: ide

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026
