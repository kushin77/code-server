# VSCode Process Orphaning - TLDR

## THE PROBLEM
- When you close VSCode GUI, **148 processes keep running** in the background
- **91 terminal sessions** become orphaned (independent process group leaders)
- Memory, file handles, and CPU still consumed
- System thinks VSCode is still active

## WHY IT HAPPENS
```
VSCode spawns terminals as independent session leaders (Ss+)
When main VSCode exits, terminals ignore the termination signal
They become children of init (PID 1) and keep running
```

## IMMEDIATE FIX (Do Now)

**Option 1: One-time cleanup**
```bash
pkill -9 code
sleep 2
ps aux | grep code  # Should be empty
```

**Option 2: Use cleanup script**
```bash
bash /home/akushnir/vscode-cleanup.sh
```

## PERMANENT FIX (Do Once)

**1. Create killer script:**
```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/kill-vscode.sh << 'EOF'
#!/bin/bash
pkill -9 -f "code"
pkill -9 -f "shellIntegration-bash"
sleep 1
EOF
chmod +x ~/.local/bin/kill-vscode.sh
```

**2. Add alias to ~/.bashrc:**
```bash
echo "alias kill-vscode='~/.local/bin/kill-vscode.sh'" >> ~/.bashrc
```

**3. Configure VSCode Settings:**
- Ctrl+, (open settings)
- Search: `terminal.integrated.enablePersistentSessions`
- Set: `false`
- Search: `terminal.integrated.closeOnExit`
- Set: `1`

## VERIFY IT WORKS

**Test:**
```bash
# Open VSCode
code

# Open 5-10 terminals
# Manually close VSCode window

# In terminal outside VSCode:
ps aux | grep code | grep -v grep | wc -l
# Should return: 0
```

**If not working:**
```bash
kill-vscode
ps aux | grep code  # Verify all dead
```

## RESULT

- ✓ VSCode closes completely
- ✓ No orphaned processes
- ✓ Memory freed immediately
- ✓ File handles released
- ✓ System responsive

## FILES TO READ

- [VSCODE_PROCESS_ORPHANING_ROOT_CAUSE.md](VSCODE_PROCESS_ORPHANING_ROOT_CAUSE.md) - Full technical analysis
- [/home/akushnir/vscode-cleanup.sh](/home/akushnir/vscode-cleanup.sh) - Cleanup tool
