# Gitspace Runtime 多镜像构建工具

Gitspace 的 Kubernetes 运行时镜像，采用多镜像策略为不同 IDE 提供专用优化镜像，支持 Taskfile 自动化构建和多种容器 Registry。

## 🚀 5 分钟快速开始

### 构建镜像

```bash
# 构建所有基础镜像
task build-all

# 构建包含预装插件的镜像
task build-all-with-extensions
```

## 📋 任务列表

| 任务 | 说明 |
|------|------|
| `task info` | 查看项目信息 |
| `task build-all` | 构建所有镜像（VSCode默认包含扩展） |
| `task build-all-with-extensions` | 构建所有镜像（含自定义扩展的VSCode） |
| `task build-base` | 构建基础镜像 |
| `task build-vscode` | 构建VSCode镜像（默认包含扩展） |
| `task build-vscode-with-extensions` | 构建自定义扩展的VSCode镜像 |
| `task build-jetbrains` | 构建JetBrains镜像 |
| `task build-cursor` | 构建Cursor镜像 |
| `task build-image` | 构建单个镜像 |

## 📚 详细使用指南

### 构建镜像

```bash
# 构建所有镜像（VSCode默认包含扩展）
task build-all

# 构建自定义扩展的VSCode镜像
task build-vscode-with-extensions

# 构建单个镜像
task build-image IMAGE=base
task build-image IMAGE=vscode
task build-image IMAGE=jetbrains
task build-image IMAGE=cursor

# 单独构建特定镜像
task build-base
task build-vscode
task build-jetbrains
task build-cursor

# 自定义VSCode扩展列表构建
task build-image IMAGE=vscode VSCODE_EXTENSIONS="ms-python.python,golang.go,esbenp.prettier-vscode"
```

## 🎯 VSCode 扩展预装指南

### 默认预装扩展

所有 VSCode 镜像（`build-vscode`、`build-all` 等）默认包含以下扩展：

```bash
task build-vscode
task build-all
```

预装常用插件：
- **Python** (`ms-python.python`) - Python 语言支持
- **TypeScript Next** (`ms-vscode.vscode-typescript-next`) - TypeScript 支持
- **Prettier** (`esbenp.prettier-vscode`) - 代码格式化
- **JSON** (`ms-vscode.vscode-json`) - JSON 文件支持

#### 自定义扩展镜像
```bash
task build-vscode-with-extensions
```
- 可以自定义扩展列表

### 自定义扩展

#### 方式一：修改 Taskfile.yml

编辑 `Taskfile.yml`，修改 `VSCODE_EXTENSIONS` 变量：

```yaml
vars:
  VSCODE_EXTENSIONS: "扩展1,扩展2,扩展3"
```

示例（预装 Python、Go、GitLens）：
```yaml
VSCODE_EXTENSIONS: "ms-python.python,golang.go,donjayamanne.githistory"
```

#### 方式二：构建时传递扩展列表

```bash
task build-image IMAGE=vscode VSCODE_EXTENSIONS="扩展1,扩展2,扩展3"
```

#### 方式三：构建带扩展的所有镜像

```bash
task build-all-with-extensions
```

## 🧪 测试构建好的镜像

### 快速测试命令

```bash
# 测试基础镜像
docker run --rm ghcr.io/ysicing/gitspace-runtime:base-latest which git

# 测试 VSCode 镜像
docker run --rm ghcr.io/ysicing/gitspace-runtime:vscode-latest code-server --version

# 启动 VSCode 服务
docker run -d -p 8080:8080 ghcr.io/ysicing/gitspace-runtime:vscode-latest
# 访问: http://localhost:8080
```

## 🔧 自定义配置

### 配置 VSCode 扩展

编辑 `Taskfile.yml` 中的 `VSCODE_EXTENSIONS` 变量：

```yaml
vars:
  VSCODE_EXTENSIONS: "ms-python.python,golang.go,esbenp.prettier-vscode"
```

然后构建：
```bash
task build-vscode-with-extensions
```

或者在构建时直接传递：

```bash
task build-image IMAGE=vscode VSCODE_EXTENSIONS="扩展1,扩展2,扩展3"
```

### 预装扩展列表

可以创建不同用途的镜像：

```bash
# Python 开发版
task build-image IMAGE=vscode VSCODE_EXTENSIONS="ms-python.python,ms-python.pylint,ms-python.flake8"

# Go 开发版
task build-image IMAGE=vscode VSCODE_EXTENSIONS="golang.go,ms-vscode.vscode-json"

# 前端开发版
task build-image IMAGE=vscode VSCODE_EXTENSIONS="esbenp.prettier-vscode,bradlc.vscode-tailwindcss"
```

## 🏗️ 镜像架构

```
ghcr.io/ysicing/gitspace-runtime:base-latest (250MB)
  ├── Ubuntu 24.04 基础镜像
  ├── 通用工具: git, curl, wget, jq
  ├── vscode 用户 (UID: 1000, GID: 1000)
  └── 通用脚本: Git 凭证管理、仓库克隆

ghcr.io/ysicing/gitspace-runtime:vscode-latest (500MB)
  ├── 继承自 base
  ├── VSCode 依赖: build-essential, python3, nodejs, npm
  ├── VSCode Server 安装和配置脚本
  └── code-server 自动安装

ghcr.io/ysicing/gitspace-runtime:jetbrains-latest (800MB)
  ├── 继承自 base
  ├── JetBrains 依赖: Java 17, X11 库等
  ├── 支持 IntelliJ IDEA, PyCharm, GoLand, WebStorm 等
  └── IDE 运行时下载和配置

ghcr.io/ysicing/gitspace-runtime:cursor-latest (550MB)
  ├── 继承自 vscode
  ├── Cursor/Windsurf 特定配置
  └── 扩展和主题预配置

ghcr.io/ysicing/gitspace-runtime:latest → vscode-latest (默认镜像)
```

## 📦 构建的镜像列表

1. **base** - 基础镜像，包含通用工具
2. **vscode** - VSCode 镜像（基于 base）
3. **jetbrains** - JetBrains IDE 镜像（基于 base）
4. **cursor** - Cursor 镜像（基于 vscode）

## 📋 镜像标签规则

镜像采用以下标签格式：

- **时间戳标签**: `ghcr.io/ysicing/gitspace-runtime:{镜像类型}-{时间戳}`
  - 示例: `ghcr.io/ysicing/gitspace-runtime:vscode-20251031-154033`
- **Latest标签**: `ghcr.io/ysicing/gitspace-runtime:{镜像类型}-latest`
  - 示例: `ghcr.io/ysicing/gitspace-runtime:vscode-latest`

时间戳格式: `YYYYMMDD-HHMMSS`
