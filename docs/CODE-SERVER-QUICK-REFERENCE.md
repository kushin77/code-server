# Code-Server Developer Quick Reference

**Everything you need is already installed!**

---

## 🐍 Python Development

```bash
# Create virtual environment
python3 -m venv myenv
source myenv/bin/activate

# Install packages (examples)
pip install flask django fastapi
pip install pytest pytest-cov
pip install pandas numpy scikit-learn

# Pre-installed tools
black --help          # Auto formatter
pylint myfile.py      # Linter
mypy myfile.py        # Type checker
pytest tests/         # Test runner
```

**Available**: Python 3.10, pip, venv, poetry, pipenv

---

## 📦 Node.js Development

```bash
# Initialize project
npm init -y

# Install packages (examples)
npm install express react webpack
npm install --save-dev typescript eslint prettier jest

# Global tools (already installed)
tsc --version         # TypeScript
webpack --version     # Bundler
eslint --help         # Linter
prettier --help       # Formatter
```

**Available**: Node 18, npm 9, TypeScript, ESLint, Prettier, Jest, Vitest

---

## 🚀 Go Development

```bash
# Create module
go mod init github.com/user/myproject

# Install packages
go get github.com/gin-gonic/gin

# Build and run
go build
./myapp

# Format and lint
goimports -w .        # Auto format + organize imports
golangci-lint run     # Linter
```

**Available**: Go 1.21, goimports, golangci-lint, dlv (debugger)

---

## 🦀 Rust Development

```bash
# New project
cargo new myapp
cd myapp

# Build and test
cargo build
cargo test
cargo run

# Formatting and checking
cargo fmt             # Format code
cargo clippy          # Linter
```

**Available**: Rust 1.73, rustfmt, clippy, cargo

---

## 🐳 Docker & Containers

```bash
# Docker CLI (connects to host daemon)
docker ps
docker build -f Dockerfile .
docker run -it ubuntu bash

# Kubernetes CLI
kubectl get pods
kubectl apply -f deployment.yaml

# Docker Compose (included)
docker-compose up -d
docker-compose logs -f
```

**Available**: Docker CLI, docker-compose, kubectl

---

## 🗄️ Database Clients

```bash
# PostgreSQL
psql -h localhost -U user -d dbname

# MySQL
mysql -h localhost -u root -p

# Redis
redis-cli
> SET key value
> GET key

# SQLite
sqlite3 mydb.db
sqlite> .tables
sqlite> SELECT * FROM users;
```

**Available**: PostgreSQL, MySQL, Redis, SQLite clients

---

## 🔧 System Tools

```bash
# File operations
git clone https://github.com/user/repo
git commit -am "message"

# HTTP requests
curl https://api.example.com/data
http GET https://api.example.com/data

# JSON processing
jq '.users[] | .name' data.json

# Text processing
grep pattern file.txt
sed 's/old/new/' file.txt
awk '{print $1}' file.txt
```

**Available**: git, curl, wget, jq, yq, grep, sed, awk, and more

---

## 🧪 Testing & Debugging

```bash
# JavaScript/TypeScript
jest               # Test runner
vitest             # Fast test runner

# Python
pytest             # Test runner
coverage           # Code coverage

# General debugging
gdb myapp          # GNU debugger
valgrind myapp     # Memory profiler
strace myapp       # System call tracer
```

**Available**: Jest, Vitest, pytest, gdb, valgrind, strace, ltrace

---

## 📝 Editors & Tools

```bash
# In terminal
vim filename.py
nano filename.py

# IDE is already open!
# Just use the VS Code editor in browser

# SSH to other systems
ssh user@host

# Terminal multiplexing
tmux new-session -s work
tmux attach -t work
```

**Available**: vim, nano, VS Code (browser), tmux, screen

---

## 🔍 Check What's Installed

```bash
# Python packages
pip list
python3 -m pip list

# Node packages globally
npm list -g --depth=0

# System packages (examples)
python3 --version
node --version
go version
rustc --version
git --version
docker --version
```

---

## ❌ I Need a Tool That's Not Listed

**Option 1: For one-time use in your profile**

```bash
# Python
pip install --user package-name

# Node
npm install -g package-name (uses your home dir cache)

# System (if sudo not blocked)
sudo apt-get install package-name  # Might not work
```

**Option 2: Request admin to add it permanently**

Contact platform team and request the tool. Examples:
- "I need gcc-arm-linux-gnueabihf for ARM development"
- "I need PostgreSQL server (not just client)"
- "I need Java for Android development"

Admin will add it to all code-server containers via:
```bash
sudo bash scripts/admin-dev-tools-add.sh --package <tool>
```

---

## 🎯 Common Workflows

### Python ML Project
```bash
python3 -m venv env
source env/bin/activate
pip install jupyter pandas numpy scikit-learn matplotlib
jupyter notebook
```

### Node React App
```bash
npm create-react-app my-app
cd my-app
npm start
```

### Go REST API
```bash
go mod init myapi
go get github.com/gin-gonic/gin
cat > main.go << 'EOF'
package main
import "github.com/gin-gonic/gin"

func main() {
    r := gin.Default()
    r.GET("/", func(c *gin.Context) {
        c.JSON(200, gin.H{"message": "hello"})
    })
    r.Run()
}
EOF
go run main.go
```

### Full-Stack Development
```bash
# Backend (Node + Express)
npm init -y
npm install express cors dotenv
# ... create server.js

# Frontend (React)
npm create-react-app frontend
cd frontend
npm start

# Database (use postgres-client)
psql -h db.example.com -U user -d mydb
```

---

## 📚 Documentation

- [Full Development Guide](../docs/DEVELOPMENT.md)
- [Full Admin Runbook](../docs/CODE-SERVER-DEV-ENVIRONMENT.md)
- [VS Code Documentation](https://code.visualstudio.com/docs)

---

## 💡 Tips & Tricks

1. **Split terminals**: Ctrl+\ (vertical) or Ctrl+Shift+\ (horizontal)
2. **Integrated terminal**: Ctrl+`
3. **Command palette**: Ctrl+Shift+P
4. **Extensions**: You already have Copilot + Copilot Chat
5. **Git integration**: Source control is in the left panel
6. **Terminal history**: Up arrow in terminal or Ctrl+Shift+H
7. **Copy terminal text**: Select + right-click or Ctrl+Shift+C

---

## 🔗 Common Links

| Resource | Link |
|----------|------|
| Code-Server | `http://code-server.kushnir.cloud` |
| Repository | `https://github.com/kushin77/code-server` |
| Issues | `https://github.com/kushin77/code-server/issues` |
| Docs | `http://docs.kushnir.cloud` |
| GitHub | `https://github.com` |

---

**Last Updated**: April 17, 2026  
**All Tools**: Pre-installed and ready to use  
**Questions?**: Contact platform@kushnir.cloud or create an issue
