# Gitspace Runtime 多镜像构建工具

Gitspace 的 Kubernetes 运行时镜像，采用多镜像策略为不同 IDE 提供专用优化镜像，支持 Taskfile 自动化构建和多种容器 Registry。

## 🚀 5 分钟快速开始

### 构建镜像

```bash
# 查看所有可用任务
task --list

# 查看项目信息
task info

# 构建所有镜像
task build-all

# 推送到镜像仓库
task push-all
```

## 📋 主要任务列表

| 任务 | 说明 |
|------|------|
| `task` | 显示所有可用任务 |
| `task info` | 查看项目信息和配置 |
| **构建任务** | |
| `task build-base` | 构建基础镜像 |
| `task build-vscode` | 构建VSCode镜像（默认包含扩展） |
| `task build-jetbrains` | 构建JetBrains镜像 |
| `task build-cursor` | 构建Cursor镜像 |
| `task build-all` | 构建所有镜像 |
| **推送任务** | |
| `task push-base` | 推送基础镜像 |
| `task push-vscode` | 推送VSCode镜像 |
| `task push-all` | 推送所有镜像 |
| **测试任务** | |
| `task test-base` | 测试基础镜像 |
| `task test-vscode` | 测试VSCode镜像 |
| `task test-all` | 测试所有镜像 |
| **多平台构建** | |
| `task buildx-setup` | 设置buildx环境 |
| `task buildx-all` | 多平台构建并推送 |
| **开发工具** | |
| `task shell-base` | 进入基础镜像shell |
| `task shell-vscode` | 进入VSCode镜像shell |
| `task clean` | 清理本地镜像 |
| `task prune` | 清理构建缓存 |

## 📚 详细使用指南

### 构建镜像

```bash
# 查看所有任务和说明
task --list

# 构建所有镜像
task build-all

# 单独构建特定镜像
task build-base        # 构建基础镜像
task build-vscode      # 构建VSCode镜像（自动依赖base）
task build-jetbrains   # 构建JetBrains镜像
task build-cursor      # 构建Cursor镜像

# 自定义VSCode扩展列表
VSCODE_EXTENSIONS="ms-python.python,golang.go" task build-vscode

# 多平台构建（amd64 + arm64）
task buildx-all
```

## 🎯 VSCode 扩展预装指南

### 默认预装扩展

所有 VSCode 镜像默认包含以下扩展：

```bash
task build-vscode
```

预装常用插件：
- **Python** (`ms-python.python`) - Python 语言支持
- **TypeScript Next** (`ms-vscode.vscode-typescript-next`) - TypeScript 支持
- **Prettier** (`esbenp.prettier-vscode`) - 代码格式化
- **JSON** (`ms-vscode.vscode-json`) - JSON 文件支持

### 自定义扩展

#### 方式一：环境变量

```bash
VSCODE_EXTENSIONS="ms-python.python,golang.go" task build-vscode
```

#### 方式二：修改 Taskfile.yml

编辑 `Taskfile.yml`，修改 `VSCODE_EXTENSIONS` 变量：

```yaml
vars:
  VSCODE_EXTENSIONS: "扩展1,扩展2,扩展3"
```

### 预装扩展示例

```bash
# Python 开发版
VSCODE_EXTENSIONS="ms-python.python,ms-python.pylint" task build-vscode

# Go 开发版
VSCODE_EXTENSIONS="golang.go,ms-vscode.vscode-json" task build-vscode

# 前端开发版
VSCODE_EXTENSIONS="esbenp.prettier-vscode,bradlc.vscode-tailwindcss" task build-vscode
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
  ├── code-server 自动安装
  └── 用途: Web 浏览器访问（端口 8089）

ghcr.io/ysicing/gitspace-runtime:vscode-desktop-latest (550MB)
  ├── 继承自 base
  ├── VSCode 依赖: build-essential, python3, nodejs, npm
  ├── ✅ OpenSSH Server 预装（端口 8088）
  ├── SSH 配置: 密码认证/公钥认证
  └── 用途: VSCode Desktop Remote-SSH 连接

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
2. **vscode** - VSCode Web 镜像（通过浏览器访问）
3. **vscode-desktop** - VSCode Desktop 镜像（通过 Remote-SSH 连接）
4. **jetbrains** - JetBrains IDE 镜像（基于 base）
5. **cursor** - Cursor 镜像（基于 vscode）

## 📋 镜像标签规则

镜像采用以下标签格式：

- **时间戳标签**: `ghcr.io/ysicing/gitspace-runtime:{镜像类型}-{时间戳}`
  - 示例: `ghcr.io/ysicing/gitspace-runtime:vscode-20251031-154033`
- **Latest标签**: `ghcr.io/ysicing/gitspace-runtime:{镜像类型}-latest`
  - 示例: `ghcr.io/ysicing/gitspace-runtime:vscode-latest`

时间戳格式: `YYYYMMDD-HHMMSS`

---

## 🔗 与 Gitness 集成

### 项目位置

此 Runtime 已集成到 Gitness 项目中: `hack/gitspace-runtime/`

### 使用 Taskfile

```bash
# 查看所有可用任务
task --list

# 构建和测试
task build-all          # 构建所有镜像
task test-all           # 测试所有镜像
task push-all           # 推送到仓库

# 多平台支持（amd64 + arm64）
task buildx-all         # 构建并推送多平台镜像

# 版本管理
VERSION=1.0.0 task tag
VERSION=1.0.0 task release

# 开发调试
task shell-vscode       # 进入镜像 shell
task inspect-vscode     # 检查镜像信息
task clean              # 清理镜像
task prune              # 清理缓存
```

### Gitness 配置

启用预装镜像以获得最佳性能:

```bash
# 在 Gitness 配置文件或环境变量中
GITSPACE_PREBUILT_IMAGES_ENABLED=true
GITSPACE_PREBUILT_IMAGES_REGISTRY=ghcr.io/ysicing/gitspace-runtime
GITSPACE_PREBUILT_IMAGE_VSCODE=vscode-latest
```

### 核心优势

- ✅ **预装 IDE** - code-server 已内置,无需下载
- ✅ **快速启动** - 从 3-5 分钟降至 30-60 秒 (5-10倍提升)
- ✅ **离线可用** - 不依赖外网
- ✅ **脚本复用** - 使用 Docker Gitspace 相同脚本
- ✅ **持久化一致** - 挂载到 HOME 目录,与 Docker 完全对齐

### 详细文档

完整文档位于 `docs/` 目录:

- [使用指南](docs/usage-guide.md) - **快速开始和常见场景** 📖
- [架构设计](docs/architecture.md) - 架构设计和技术实现
- [Gitness 集成](docs/gitness-integration-plan.md) - Gitness 集成方案

---

**维护者**: Gitness Team, @ysicing
**更新时间**: 2025-11-06
**版本**: v1.0
