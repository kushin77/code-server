// apps/backend/src/services/workspace-auto-config/detection-engine.ts
// @file: Workspace project type detection engine for Issue #1048
// Analyzes repository structure and detects project type < 2 seconds
import * as fs from "fs";
export var ProjectType;
(function (ProjectType) {
    ProjectType["NODE_TYPESCRIPT"] = "node-typescript";
    ProjectType["NODE_JAVASCRIPT"] = "node-javascript";
    ProjectType["PYTHON"] = "python";
    ProjectType["PYTHON_DJANGO"] = "python-django";
    ProjectType["GO"] = "go";
    ProjectType["RUST"] = "rust";
    ProjectType["JAVA"] = "java";
    ProjectType["JAVA_SPRING"] = "java-spring";
    ProjectType["CPP"] = "cpp";
    ProjectType["CSHARP"] = "csharp";
    ProjectType["PHP"] = "php";
    ProjectType["RUBY"] = "ruby";
    ProjectType["UNKNOWN"] = "unknown";
})(ProjectType || (ProjectType = {}));
export class ProjectDetectionEngine {
    constructor(workspaceRoot) {
        this.detectionRules = new Map();
        this.workspaceRoot = workspaceRoot;
        this.initializeDetectionRules();
    }
    initializeDetectionRules() {
        // Node.js + TypeScript
        this.detectionRules.set(ProjectType.NODE_TYPESCRIPT, {
            type: ProjectType.NODE_TYPESCRIPT,
            priority: 10,
            requiredFiles: ["package.json"],
            indicatorFiles: [
                "tsconfig.json",
                "src/",
                "types/",
                "dist/",
                "*.ts",
            ],
            detectFn: (files) => {
                const hasPackageJson = files.includes("package.json");
                const hasTsConfig = files.includes("tsconfig.json");
                const hasTypeScriptFiles = files.some((f) => f.endsWith(".ts") && !f.endsWith(".d.ts"));
                return hasPackageJson && (hasTsConfig || hasTypeScriptFiles);
            },
        });
        // Node.js + JavaScript
        this.detectionRules.set(ProjectType.NODE_JAVASCRIPT, {
            type: ProjectType.NODE_JAVASCRIPT,
            priority: 9,
            requiredFiles: ["package.json"],
            indicatorFiles: ["*.js", "src/", "lib/", "dist/"],
            detectFn: (files) => files.includes("package.json") && !files.includes("tsconfig.json"),
        });
        // Python
        this.detectionRules.set(ProjectType.PYTHON, {
            type: ProjectType.PYTHON,
            priority: 10,
            requiredFiles: [],
            indicatorFiles: ["requirements.txt", "setup.py", "pyproject.toml", "Pipfile", "poetry.lock", "*.py"],
            detectFn: (files) => {
                const pythonIndicators = [
                    "requirements.txt",
                    "setup.py",
                    "pyproject.toml",
                    "Pipfile",
                    "poetry.lock",
                ];
                return pythonIndicators.some((f) => files.includes(f)) || files.some((f) => f.endsWith(".py"));
            },
        });
        // Python + Django
        this.detectionRules.set(ProjectType.PYTHON_DJANGO, {
            type: ProjectType.PYTHON_DJANGO,
            priority: 11,
            requiredFiles: [],
            indicatorFiles: ["manage.py", "settings.py", "wsgi.py", "django.conf"],
            detectFn: (files) => files.includes("manage.py") || files.includes("wsgi.py"),
        });
        // Go
        this.detectionRules.set(ProjectType.GO, {
            type: ProjectType.GO,
            priority: 10,
            requiredFiles: ["go.mod"],
            indicatorFiles: ["go.sum", "*.go", "cmd/"],
            detectFn: (files) => files.includes("go.mod"),
        });
        // Rust
        this.detectionRules.set(ProjectType.RUST, {
            type: ProjectType.RUST,
            priority: 10,
            requiredFiles: ["Cargo.toml"],
            indicatorFiles: ["Cargo.lock", "src/", "*.rs"],
            detectFn: (files) => files.includes("Cargo.toml"),
        });
        // Java
        this.detectionRules.set(ProjectType.JAVA, {
            type: ProjectType.JAVA,
            priority: 10,
            requiredFiles: [],
            indicatorFiles: ["pom.xml", "build.gradle", "*.java", "src/main/java"],
            detectFn: (files) => files.includes("pom.xml") || files.includes("build.gradle"),
        });
        // Java + Spring
        this.detectionRules.set(ProjectType.JAVA_SPRING, {
            type: ProjectType.JAVA_SPRING,
            priority: 11,
            requiredFiles: [],
            indicatorFiles: ["pom.xml", "application.properties", "application.yml"],
            detectFn: (files) => files.includes("pom.xml") && files.includes("application.properties"),
        });
        // C++
        this.detectionRules.set(ProjectType.CPP, {
            type: ProjectType.CPP,
            priority: 9,
            requiredFiles: [],
            indicatorFiles: ["CMakeLists.txt", "Makefile", "*.cpp", "*.h"],
            detectFn: (files) => files.includes("CMakeLists.txt") || files.includes("Makefile"),
        });
        // C#
        this.detectionRules.set(ProjectType.CSHARP, {
            type: ProjectType.CSHARP,
            priority: 9,
            requiredFiles: [],
            indicatorFiles: ["*.csproj", "*.sln", "*.cs"],
            detectFn: (files) => files.some((f) => f.endsWith(".csproj") || f.endsWith(".sln")),
        });
        // PHP
        this.detectionRules.set(ProjectType.PHP, {
            type: ProjectType.PHP,
            priority: 8,
            requiredFiles: [],
            indicatorFiles: ["composer.json", "*.php", "index.php"],
            detectFn: (files) => files.includes("composer.json") || files.some((f) => f.endsWith(".php")),
        });
        // Ruby
        this.detectionRules.set(ProjectType.RUBY, {
            type: ProjectType.RUBY,
            priority: 8,
            requiredFiles: [],
            indicatorFiles: ["Gemfile", "Rakefile", "*.rb"],
            detectFn: (files) => files.includes("Gemfile") || files.some((f) => f.endsWith(".rb")),
        });
    }
    async detectProjectType(timeout = 2000) {
        const startTime = Date.now();
        const detectedFiles = this.getRepositoryFiles();
        let bestMatch = {
            type: ProjectType.UNKNOWN,
            confidence: 0,
        };
        // Check all detection rules in priority order
        const sortedRules = Array.from(this.detectionRules.values()).sort((a, b) => b.priority - a.priority);
        for (const rule of sortedRules) {
            // Timeout protection
            if (Date.now() - startTime > timeout) {
                break;
            }
            try {
                if (rule.detectFn(detectedFiles)) {
                    const confidence = this.calculateConfidence(rule, detectedFiles);
                    if (confidence > bestMatch.confidence) {
                        bestMatch = {
                            type: rule.type,
                            confidence,
                        };
                    }
                }
            }
            catch (error) {
                // Silently skip detection rules that error
                continue;
            }
        }
        return {
            type: bestMatch.type,
            confidence: bestMatch.confidence,
            detectedFiles,
            timestamp: Date.now(),
        };
    }
    getRepositoryFiles() {
        const files = [];
        try {
            const entries = fs.readdirSync(this.workspaceRoot, { withFileTypes: true });
            for (const entry of entries) {
                if (entry.isFile()) {
                    files.push(entry.name);
                }
                else if (entry.isDirectory() && !entry.name.startsWith(".")) {
                    files.push(`${entry.name}/`);
                }
            }
        }
        catch (error) {
            // Return empty array if root read fails
        }
        return files;
    }
    calculateConfidence(rule, detectedFiles) {
        let confidence = 0;
        // Check required files (essential for detection)
        if (rule.requiredFiles.length > 0) {
            const requiredFound = rule.requiredFiles.filter((f) => detectedFiles.includes(f)).length;
            confidence += (requiredFound / rule.requiredFiles.length) * 50;
        }
        // Check indicator files (boost confidence)
        if (rule.indicatorFiles.length > 0) {
            const indicatorsFound = rule.indicatorFiles.filter((f) => detectedFiles.some((detected) => detected.includes(f.replace(/\/$/, "")))).length;
            confidence += (indicatorsFound / rule.indicatorFiles.length) * 50;
        }
        return Math.min(confidence, 100);
    }
    getProfileForType(type) {
        const profiles = {
            [ProjectType.NODE_TYPESCRIPT]: {
                type: ProjectType.NODE_TYPESCRIPT,
                extensions: [
                    "ms-vscode.vscode-typescript-next",
                    "esbenp.prettier-vscode",
                    "ms-eslint.vscode-eslint",
                    "GitHub.copilot",
                ],
                settings: {
                    "[typescript]": {
                        "editor.defaultFormatter": "esbenp.prettier-vscode",
                        "editor.formatOnSave": true,
                    },
                    "typescript.tsdk": "node_modules/typescript/lib",
                    "typescript.enablePromptUseWorkspaceTsdk": true,
                },
                tasks: [
                    {
                        label: "npm: build",
                        command: "npm",
                        args: ["run", "build"],
                    },
                    {
                        label: "npm: test",
                        command: "npm",
                        args: ["test"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Launch Program",
                        type: "node",
                        request: "launch",
                        program: "${workspaceFolder}/dist/index.js",
                        args: [],
                        cwd: "${workspaceFolder}",
                    },
                ],
            },
            [ProjectType.NODE_JAVASCRIPT]: {
                type: ProjectType.NODE_JAVASCRIPT,
                extensions: ["esbenp.prettier-vscode", "ms-eslint.vscode-eslint", "GitHub.copilot"],
                settings: {
                    "[javascript]": {
                        "editor.defaultFormatter": "esbenp.prettier-vscode",
                        "editor.formatOnSave": true,
                    },
                },
                tasks: [
                    {
                        label: "npm: build",
                        command: "npm",
                        args: ["run", "build"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Launch Program",
                        type: "node",
                        request: "launch",
                        program: "${workspaceFolder}/index.js",
                    },
                ],
            },
            [ProjectType.PYTHON]: {
                type: ProjectType.PYTHON,
                extensions: ["ms-python.python", "ms-python.vscode-pylance", "GitHub.copilot"],
                settings: {
                    "python.linting.enabled": true,
                    "python.linting.pylintEnabled": true,
                    "[python]": {
                        "editor.defaultFormatter": "ms-python.python",
                        "editor.formatOnSave": true,
                    },
                },
                tasks: [
                    {
                        label: "python: test",
                        command: "python",
                        args: ["-m", "pytest"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Python: Current File",
                        type: "python",
                        request: "launch",
                        program: "${file}",
                        cwd: "${workspaceFolder}",
                    },
                ],
            },
            [ProjectType.GO]: {
                type: ProjectType.GO,
                extensions: ["golang.go", "GitHub.copilot"],
                settings: {
                    "[go]": {
                        "editor.formatOnSave": true,
                        "editor.codeActionsOnSave": {
                            "source.organizeImports": true,
                        },
                    },
                },
                tasks: [
                    {
                        label: "go: build",
                        command: "go",
                        args: ["build", "./..."],
                    },
                    {
                        label: "go: test",
                        command: "go",
                        args: ["test", "./..."],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Launch Package",
                        type: "go",
                        request: "launch",
                        program: "${fileDirname}",
                        cwd: "${workspaceFolder}",
                    },
                ],
            },
            [ProjectType.RUST]: {
                type: ProjectType.RUST,
                extensions: ["rust-lang.rust-analyzer", "GitHub.copilot"],
                settings: {
                    "[rust]": {
                        "editor.formatOnSave": true,
                        "editor.defaultFormatter": "rust-lang.rust-analyzer",
                    },
                },
                tasks: [
                    {
                        label: "cargo: build",
                        command: "cargo",
                        args: ["build"],
                    },
                    {
                        label: "cargo: test",
                        command: "cargo",
                        args: ["test"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Rust Debug",
                        type: "lldb",
                        request: "launch",
                        program: "${workspaceFolder}/target/debug/${workspaceFolderBasename}",
                    },
                ],
            },
            [ProjectType.JAVA]: {
                type: ProjectType.JAVA,
                extensions: ["redhat.java", "vscjava.vscode-maven", "GitHub.copilot"],
                settings: {
                    "[java]": {
                        "editor.formatOnSave": true,
                    },
                },
                tasks: [
                    {
                        label: "mvn: build",
                        command: "mvn",
                        args: ["clean", "build"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Java Debug",
                        type: "java",
                        request: "launch",
                        program: "main",
                    },
                ],
            },
            [ProjectType.PYTHON_DJANGO]: {
                type: ProjectType.PYTHON_DJANGO,
                extensions: ["ms-python.python", "ms-python.vscode-pylance", "ms-python.django", "GitHub.copilot"],
                settings: {
                    "python.linting.enabled": true,
                    "[python]": {
                        "editor.defaultFormatter": "ms-python.python",
                        "editor.formatOnSave": true,
                    },
                },
                tasks: [
                    {
                        label: "django: migrate",
                        command: "python",
                        args: ["manage.py", "migrate"],
                    },
                    {
                        label: "django: runserver",
                        command: "python",
                        args: ["manage.py", "runserver"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Django",
                        type: "python",
                        request: "launch",
                        program: "${workspaceFolder}/manage.py",
                        args: ["runserver"],
                    },
                ],
            },
            [ProjectType.JAVA_SPRING]: {
                type: ProjectType.JAVA_SPRING,
                extensions: ["redhat.java", "vscjava.vscode-maven", "Pivotal.vscode-spring-boot", "GitHub.copilot"],
                settings: {
                    "[java]": {
                        "editor.formatOnSave": true,
                    },
                },
                tasks: [
                    {
                        label: "mvn: spring-boot:run",
                        command: "mvn",
                        args: ["spring-boot:run"],
                    },
                    {
                        label: "mvn: test",
                        command: "mvn",
                        args: ["test"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Spring Boot",
                        type: "java",
                        request: "launch",
                        preLaunchTask: "mvn: spring-boot:run",
                    },
                ],
            },
            [ProjectType.CPP]: {
                type: ProjectType.CPP,
                extensions: ["ms-vscode.cpptools", "GitHub.copilot"],
                settings: {
                    "[cpp]": {
                        "editor.formatOnSave": true,
                        "editor.defaultFormatter": "ms-vscode.cpptools",
                    },
                },
                tasks: [
                    {
                        label: "C++: build",
                        command: "cmake",
                        args: ["--build", "build"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "C++ Debug",
                        type: "cppdbg",
                        request: "launch",
                        program: "${workspaceFolder}/build/main",
                    },
                ],
            },
            [ProjectType.CSHARP]: {
                type: ProjectType.CSHARP,
                extensions: ["ms-dotnettools.csharp", "ms-vscode.csharp", "GitHub.copilot"],
                settings: {
                    "[csharp]": {
                        "editor.formatOnSave": true,
                        "editor.defaultFormatter": "ms-dotnettools.csharp",
                    },
                },
                tasks: [
                    {
                        label: "dotnet: build",
                        command: "dotnet",
                        args: ["build"],
                    },
                    {
                        label: "dotnet: test",
                        command: "dotnet",
                        args: ["test"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: ".NET Debug",
                        type: "coreclr",
                        request: "launch",
                        program: "${workspaceFolder}/bin/Debug/net6.0/${workspaceFolderBasename}.dll",
                    },
                ],
            },
            [ProjectType.PHP]: {
                type: ProjectType.PHP,
                extensions: ["felixbecker.php-intellisense", "felixbecker.php-debug", "GitHub.copilot"],
                settings: {
                    "[php]": {
                        "editor.formatOnSave": true,
                    },
                },
                tasks: [
                    {
                        label: "php: serve",
                        command: "php",
                        args: ["-S", "localhost:8000"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "PHP Debug",
                        type: "php",
                        request: "launch",
                        port: 9003,
                    },
                ],
            },
            [ProjectType.RUBY]: {
                type: ProjectType.RUBY,
                extensions: ["rebornix.ruby", "castwide.solargraph", "GitHub.copilot"],
                settings: {
                    "[ruby]": {
                        "editor.formatOnSave": true,
                        "editor.defaultFormatter": "castwide.solargraph",
                    },
                },
                tasks: [
                    {
                        label: "ruby: test",
                        command: "ruby",
                        args: ["-Ilib", "test"],
                    },
                ],
                debugConfigurations: [
                    {
                        name: "Ruby Debug",
                        type: "ruby",
                        request: "launch",
                        program: "${workspaceFolder}/app.rb",
                    },
                ],
            },
            // Fallback for all unrecognized types
            [ProjectType.UNKNOWN]: {
                type: ProjectType.UNKNOWN,
                extensions: ["GitHub.copilot", "ms-vscode.cpptools"],
                settings: {},
                tasks: [],
                debugConfigurations: [],
            },
        };
        return profiles[type] || profiles[ProjectType.UNKNOWN];
    }
}
//# sourceMappingURL=detection-engine.js.map