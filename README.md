# Gitspace Runtime 多镜像构建工具

Gitspace 的 Kubernetes 运行时镜像，采用多镜像策略为不同 IDE 提供专用优化镜像，支持 Taskfile 自动化构建和多种容器 Registry。

## 🚀 5 分钟快速开始

### 1. 安装 Task

```bash
# macOS
brew install go-task/tap/go-task

# Linux
curl -sL https://github.com/go-task/task/releases/download/v3.37.2/task_linux_amd64.tar.gz | tar xz
sudo mv task /usr/local/bin/

# Windows (Chocolatey)
choco install go-task
```

### 2. 查看可用任务

```bash
task --list
```

### 3. 构建镜像

```bash
# 构建所有基础镜像
task build-all

# 构建包含预装插件的镜像
task build-all-with-extensions
```

### 4. 测试镜像

```bash
# 使用测试脚本
./test-images.sh ttl.sh/ysicing/gitspace-runtime latest

# 或者使用 Taskfile
task test-images
```

### 5. 推送到 Registry

```bash
# 构建镜像
task build-all

# 推送到 ghcr.io (需要先登录)
docker login ghcr.io -u <username>
docker push ghcr.io/ysicing/gitspace-runtime:base-latest
docker push ghcr.io/ysicing/gitspace-runtime:vscode-latest

# 或推送到 ttl.sh (无需登录)
docker push ttl.sh/ysicing/gitspace-runtime:base-latest
docker push ttl.sh/ysicing/gitspace-runtime:vscode-latest
```

## 📦 Registry 支持

### ghcr.io (推荐用于生产)
- ✅ GitHub 集成
- ✅ 永久存储
- ✅ 私有/公开可选
- ✅ 需要登录

```bash
docker login ghcr.io -u <username>
task build-all
docker push ghcr.io/ysicing/gitspace-runtime:base-latest
docker push ghcr.io/ysicing/gitspace-runtime:vscode-latest
```

### ttl.sh (推荐用于测试)
- ✅ 无需注册
- ✅ 无需登录
- ✅ 自动 24 小时过期
- ❌ 永久存储

```bash
task build-all
docker push ttl.sh/ysicing/gitspace-runtime:base-latest
docker push ttl.sh/ysicing/gitspace-runtime:vscode-latest
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

### 推送镜像

```bash
# 构建镜像后，手动推送
task build-all

# 推送到 ttl.sh (无需登录)
docker push ttl.sh/ysicing/gitspace-runtime:base-$(task --list -l | grep IMAGE_TAG | awk '{print $3}')
docker push ttl.sh/ysicing/gitspace-runtime:vscode-$(task --list -l | grep IMAGE_TAG | awk '{print $3}')

# 推送到 ghcr.io (需要先登录)
docker login ghcr.io -u <username>
docker push ghcr.io/ysicing/gitspace-runtime:base-latest
docker push ghcr.io/ysicing/gitspace-runtime:vscode-latest
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

### 扩展 ID 获取方法

#### 方法一：VSCode 市场
1. 访问 [VSCode 市场](https://marketplace.visualstudio.com/vscode)
2. 搜索需要的扩展
3. 点击扩展进入详情页
4. 复制 URL 中的发布者.扩展名，例如：
   - URL: `https://marketplace.visualstudio.com/items?itemName=ms-python.python`
   - 扩展 ID: `ms-python.python`

#### 方法二：命令行查询
```bash
code-server --list-extensions
```

### 常用扩展推荐

#### 编程语言支持
```bash
# Python
ms-python.python

# Go
golang.go

# Java
redhat.java

# C/C++
ms-vscode.cpptools

# Rust
rust-lang.rust-analyzer

# TypeScript/JavaScript
ms-vscode.vscode-typescript-next
```

#### 实用工具
```bash
# GitLens - Git 增强
donjayamanne.githistory

# Prettier - 代码格式化
esbenp.prettier-vscode

# ESLint - 代码检查
dbaeumer.vscode-eslint

# Docker 支持
ms-azuretools.vscode-docker

# Kubernetes 支持
ms-kubernetes-tools.vscode-kubernetes-tools
```

#### 主题和图标
```bash
# Dracula 主题
dracula-theme.theme-dracula

# Material Icon Theme
pkief.material-icon-theme
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

### 完整测试脚本

```bash
# 测试所有镜像
./test-images.sh ghcr.io/ysicing/gitspace-runtime latest

# 测试 ttl.sh 镜像
./test-images.sh ttl.sh/ysicing/gitspace-runtime latest
```

## 🔧 自定义配置

### 修改镜像仓库

在 `Taskfile.yml` 中修改 `vars.REGISTRY`:

```yaml
vars:
  REGISTRY: your-registry.com/your-namespace/gitspace-runtime
```

### 使用不同的镜像标签

```bash
# 构建时使用特定的 IMAGE_TAG
task IMAGE_TAG=custom-tag build-all
```

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

## 🔍 任务依赖关系

```
build-all
├── build-base (依赖构建完成)
├── build-vscode (依赖 build-base)
│   └── build-cursor (依赖 build-vscode)
└── build-jetbrains (依赖 build-base，与其他任务并行)
```

## 💡 使用示例

```bash
# 1. 查看项目信息
task info

# 2. 构建所有镜像（基础版）
task build-all

# 3. 构建包含预装插件的镜像
task build-all-with-extensions

# 4. 构建单个镜像
task build-image IMAGE=base
task build-image IMAGE=vscode

# 5. 手动推送镜像
docker push ttl.sh/ysicing/gitspace-runtime:base-latest
docker push ttl.sh/ysicing/gitspace-runtime:vscode-latest
```

## 🔄 GitHub Actions 自动化

### 触发条件

- 推送到 `master` 或 `main` 分支时自动构建

### 配置

自动使用以下配置：
- **Registry**: `ghcr.io/ysicing/gitspace-runtime`
- **VSCode 扩展**: `ms-python.python,ms-vscode.vscode-typescript-next,esbenp.prettier-vscode,ms-vscode.vscode-json`

### 构建流程

1. 自动登录 ghcr.io
2. 构建 base 镜像并推送
3. 基于 base 构建 vscode 和 jetbrains 镜像
4. 基于 vscode 构建 cursor 镜像
5. 推送所有镜像到 ghcr.io
6. 自动设置 latest 标签

## 📝 目录结构

```
gitspace-runtime/
├── Taskfile.yml                    # 主要配置文件
├── test-images.sh                  # 镜像测试脚本
├── .github/
│   └── workflows/
│       └── build-and-push.yml      # GitHub Actions 工作流
├── base/                      # 基础镜像
│   ├── Dockerfile
│   └── scripts/
│       ├── setup-git-credentials.sh
│       └── clone-repository.sh
├── vscode/                    # VSCode 镜像 (支持插件预装)
│   ├── Dockerfile
│   ├── init-vscode.sh
│   └── scripts/
│       ├── install-vscode-server.sh
│       └── configure-vscode.sh
├── jetbrains/                 # JetBrains 镜像
│   ├── Dockerfile
│   └── scripts/
└── cursor/                    # Cursor 镜像
    └── Dockerfile
```

## 🎉 发布示例

### 发布到 ghcr.io (用于生产)

```bash
docker login ghcr.io -u <username>
task build-all
docker push ghcr.io/ysicing/gitspace-runtime:base-latest
docker push ghcr.io/ysicing/gitspace-runtime:vscode-latest
echo "发布完成: https://ghcr.io/ysicing/gitspace-runtime"
```

### 发布到 ttl.sh (用于测试)

```bash
task build-all-with-extensions
docker push ttl.sh/ysicing/gitspace-runtime:base-latest
docker push ttl.sh/ysicing/gitspace-runtime:vscode-latest
echo "发布完成: https://ttl.sh/ysicing/gitspace-runtime"
```

## 🐛 常见问题

### Q: 构建失败怎么办？
A: 检查 Docker 是否正常运行，确保有足够的磁盘空间

### Q: 推送失败怎么办？
A: ghcr.io 需要先登录：`docker login ghcr.io -u <username>`，ttl.sh 无需登录

### Q: 如何手动推送镜像？
A: 构建完成后使用 `docker push <镜像地址>` 命令推送

## 💡 提示

1. **生产阶段** - 使用 `ghcr.io` 永久存储，私有管理
2. **测试阶段** - 使用 `ttl.sh` 快速测试，无需登录
3. **扩展插件** - 根据项目需求预装 VSCode 插件
4. **镜像标签** - 每次构建自动生成时间戳标签，避免冲突

## 📚 参考资源

- [Taskfile 官方文档](https://taskfile.dev/)
- [Docker 构建文档](https://docs.docker.com/engine/reference/commandline/build/)
- [VSCode 扩展市场](https://marketplace.visualstudio.com/vscode)
- [Code-Server 文档](https://code-server.dev/)

## 🆕 更新日志

### [2.0.0] - 2025-10-31

#### ✨ 新增功能

**Taskfile**
- ✅ 新增 `build-vscode-with-extensions` 任务 - 构建预装插件的 VSCode 镜像
- ✅ 新增 `build-all-with-extensions` 任务 - 构建所有镜像（包含预装插件的VSCode）
- ✅ 支持自定义 VSCode 扩展列表构建
- ✅ 支持在构建时传递 `VSCODE_EXTENSIONS` 环境变量
- ✅ 简化任务列表，专注于构建功能（从 23 个任务简化为 8 个）
- ✅ 移除推送、测试、清理等任务，使用原生 Docker 命令

**Docker 镜像**
- ✅ 修复所有 Dockerfile 中的硬编码基础镜像引用
- ✅ VSCode Dockerfile 新增 `VSCODE_EXTENSIONS` 参数支持
- ✅ 修复构建参数传递问题
- ✅ 预装插件逻辑：支持在构建时自动安装指定扩展

**GitHub Actions**
- ✅ 简化工作流，从 4 个 jobs 合并为 1 个
- ✅ 默认推送到 ghcr.io（而非 ttl.sh）
- ✅ 自动登录 ghcr.io 进行推送
- ✅ 固定配置，无需手动输入参数

**文档**
- ✅ 合并所有文档到 README.md
- ✅ 提供常用扩展推荐列表

#### 🔧 修改内容

**Taskfile.yml**
- 添加 `VSCODE_EXTENSIONS` 变量
- 更新所有镜像的构建依赖关系
- 增强 `build-image` 任务支持扩展参数
- 新增预装扩展的构建任务

**Dockerfile**
- **vscode/Dockerfile**: 添加 `ARG VSCODE_EXTENSIONS`，支持预装扩展
- **cursor/Dockerfile**: 修复基础镜像引用
- **jetbrains/Dockerfile**: 修复基础镜像引用

#### 📦 预装扩展

默认预装扩展列表（`build-vscode-with-extensions`）：
- `ms-python.python` - Python 语言支持
- `ms-vscode.vscode-typescript-next` - TypeScript 支持
- `esbenp.prettier-vscode` - 代码格式化
- `ms-vscode.vscode-json` - JSON 文件支持

#### 🐛 修复问题

1. **Dockerfile 基础镜像引用错误** - 所有 Dockerfile 现在使用 ARG 参数而不是硬编码引用
2. **Taskfile 变量传递问题** - 修复了 `vars` 语法和变量传递
3. **YAML 语法错误** - 修复了所有引号嵌套和映射值错误

#### 🎯 兼容性

- 与旧版本完全兼容（基础镜像构建不受影响）
- 现有 Dockerfile 无需修改即可使用
- 向后兼容 `task build-all` 命令

---

**Copyright (c) 2025 Gitness Team. Licensed under Apache 2.0 / AGPL 3.0.**
