# Gitspace Runtime 统一架构设计

## 目标

将 Docker Gitspace 的镜像构建和脚本抽取到 `hack/gitspace-runtime`，使 K8s Gitspace 可以:
1. ✅ 开箱即用 (镜像预装 IDE，无需下载)
2. ✅ 与 Docker Gitspace 100% 行为一致
3. ✅ 持久化策略一致 (挂载到 HOME 目录)
4. ✅ 用户体验一致

---

## 目录结构设计

```
hack/gitspace-runtime/
├── README.md                          # Runtime 使用说明
├── Makefile                           # 统一构建命令
│
├── images/                            # 镜像定义
│   ├── base/                          # 基础镜像 (共享层)
│   │   ├── Dockerfile                 # Alpine/Ubuntu 基础 + 通用工具
│   │   └── scripts/                   # 基础脚本
│   │       ├── setup-git-credentials.sh
│   │       ├── clone-repository.sh
│   │       ├── detect-devcontainer-user.sh
│   │       └── create-user-dynamic.sh
│   │
│   ├── vscode/                        # VS Code 镜像
│   │   ├── Dockerfile                 # 预装 code-server
│   │   ├── init-vscode.sh             # 初始化脚本
│   │   ├── install-vscode-server.sh   # VS Code Server 安装
│   │   ├── configure-vscode.sh        # VS Code 配置
│   │   └── extensions/                # 预装扩展列表
│   │
│   ├── cursor/                        # Cursor 镜像
│   │   ├── Dockerfile
│   │   ├── init-cursor.sh
│   │   └── ...
│   │
│   └── jetbrains/                     # JetBrains 镜像
│       ├── Dockerfile
│       ├── init-jetbrains.sh
│       └── ...
│
├── scripts/                           # 通用脚本库
│   ├── common/                        # Docker Gitspace 使用的脚本
│   │   ├── clone_code.sh
│   │   ├── setup_git_credentials.sh
│   │   ├── setup_ssh_server.sh
│   │   ├── manage_user.sh
│   │   └── ...
│   │
│   └── ide/                           # IDE 专用脚本
│       ├── vscode/
│       ├── cursor/
│       └── jetbrains/
│
├── manifests/                         # K8s 部署清单
│   ├── base/                          # 基础资源
│   │   ├── namespace.yaml
│   │   ├── pvc.yaml
│   │   └── configmap.yaml
│   │
│   ├── vscode/                        # VS Code 部署
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   │
│   └── kustomization.yaml
│
├── build/                             # 构建脚本
│   ├── build-images.sh                # 构建所有镜像
│   ├── push-images.sh                 # 推送镜像
│   └── versions.sh                    # 版本管理
│
└── docs/                              # 文档
    ├── architecture.md                # 架构设计
    ├── image-build.md                 # 镜像构建指南
    └── deployment.md                  # 部署指南
```

---

## 关键设计原则

### 1. 镜像分层策略

```
┌──────────────────────────────────────┐
│  IDE 层 (vscode/cursor/jetbrains)   │ ← 预装 IDE + 扩展
├──────────────────────────────────────┤
│        Base 层 (共享基础)             │ ← 通用工具 + 脚本
├──────────────────────────────────────┤
│     Alpine/Ubuntu 基础镜像            │ ← 最小化基础系统
└──────────────────────────────────────┘
```

**优势**:
- 共享 Base 层，减少重复
- 每个 IDE 独立构建和版本管理
- 易于扩展新的 IDE

### 2. 脚本复用策略

**从 Docker Gitspace 提取**:
```bash
/Users/ysicing/go/src/github.com/yunop-com/gitness/app/gitspace/orchestrator/utils/script_templates/
├── clone_code.sh          → hack/gitspace-runtime/scripts/common/clone-code.sh
├── setup_git_credentials.sh → hack/gitspace-runtime/scripts/common/setup-git-credentials.sh
├── manage_user.sh         → hack/gitspace-runtime/scripts/common/manage-user.sh
├── install_vscode_web.sh  → hack/gitspace-runtime/images/vscode/install-vscode.sh
└── ...
```

**调整内容**:
1. 路径标准化: `/usr/local/gitspace/scripts/`
2. HOME 目录对齐: 使用 `$HOME` 而不是 `/workspaces`
3. 添加错误处理和日志

### 3. 镜像预装 IDE 策略

#### VS Code Server 预装

```dockerfile
# Dockerfile for vscode
FROM gitness/gitspace-base:latest

# 预装 code-server
ARG CODE_SERVER_VERSION=4.23.1
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=${CODE_SERVER_VERSION}

# 预装常用扩展
COPY extensions.txt /tmp/
RUN while read ext; do \
      code-server --install-extension "$ext"; \
    done < /tmp/extensions.txt

# 复制 IDE 专用脚本
COPY init-vscode.sh /usr/local/bin/gitspace-init.sh
COPY install-vscode-server.sh /usr/local/gitspace/scripts/vscode/
COPY configure-vscode.sh /usr/local/gitspace/scripts/vscode/

RUN chmod +x /usr/local/bin/gitspace-init.sh

WORKDIR /home/vscode
CMD ["/usr/local/bin/gitspace-init.sh"]
```

**关键点**:
- ✅ 预装 code-server (无需运行时下载)
- ✅ 预装常用扩展 (加速启动)
- ✅ 脚本打包进镜像
- ✅ 默认工作目录 = HOME

---

## 与当前 gitspace-runtime 的整合

### 当前 gitspace-runtime 结构

```
/Users/ysicing/Work/github/ysicing/gitspace-runtime/
├── base/                  # 当前基础层
│   ├── Dockerfile
│   └── scripts/
├── vscode/                # 当前 vscode 层
│   └── init-vscode.sh
└── examples/              # 当前示例
    └── gitspace-vscode.yaml
```

### 整合方案

**方案 A: 原地增强** (推荐)
```bash
# 保持当前结构，增强功能
gitspace-runtime/
├── base/                          # 增强基础层
│   ├── Dockerfile                 # 合并 Docker Gitspace 的基础工具
│   └── scripts/
│       ├── common/                # 新增：Docker Gitspace 脚本
│       │   ├── clone-code.sh      # 从 Docker Gitspace 提取
│       │   ├── setup-git-credentials.sh
│       │   ├── manage-user.sh
│       │   └── ...
│       ├── detect-devcontainer-user.sh  # 已有
│       └── create-user-dynamic.sh       # 已有
│
├── vscode/                        # 增强 vscode 层
│   ├── Dockerfile                 # 新增：预装 code-server
│   ├── init-vscode.sh             # 已有，已调整
│   ├── install-vscode-server.sh   # 新增：从 Docker Gitspace 提取
│   ├── configure-vscode.sh        # 新增：从 Docker Gitspace 提取
│   └── extensions.txt             # 新增：预装扩展列表
│
├── cursor/                        # 新增
├── jetbrains/                     # 新增
│
├── build/                         # 新增：构建工具
│   ├── build-all.sh
│   └── versions.sh
│
└── docs/                          # 增强文档
    └── docker-gitspace-alignment.md
```

**方案 B: 创建 hack/gitspace-runtime 子目录**
```bash
gitspace-runtime/
└── hack/
    └── gitspace-runtime/          # 新的统一 runtime
        ├── images/
        ├── scripts/
        └── manifests/
```

**推荐方案 A**，因为:
1. 当前项目已经是 gitspace-runtime
2. 避免嵌套 `gitspace-runtime/hack/gitspace-runtime`
3. 直接增强现有结构更清晰

---

## 实施计划

### Phase 1: 提取 Docker Gitspace 脚本 ✅

**目标**: 将 Docker Gitspace 的脚本复制到 gitspace-runtime

```bash
# 从 Gitness 项目提取脚本
SOURCE="/Users/ysicing/go/src/github.com/yunop-com/gitness/app/gitspace/orchestrator/utils/script_templates"
TARGET="/Users/ysicing/Work/github/ysicing/gitspace-runtime/base/scripts/docker-gitspace"

mkdir -p "$TARGET"

# 提取核心脚本
cp "$SOURCE/clone_code.sh" "$TARGET/clone-code.sh"
cp "$SOURCE/setup_git_credentials.sh" "$TARGET/setup-git-credentials.sh"
cp "$SOURCE/manage_user.sh" "$TARGET/manage-user.sh"
cp "$SOURCE/install_vscode_web.sh" "$TARGET/install-vscode-web.sh"
cp "$SOURCE/run_vscode_web.sh" "$TARGET/run-vscode-web.sh"
cp "$SOURCE/setup_vscode_extensions.sh" "$TARGET/setup-vscode-extensions.sh"
# ... 其他脚本
```

### Phase 2: 创建统一的基础镜像 🔄

**目标**: 合并 Docker Gitspace 和当前 runtime 的基础层

```dockerfile
# base/Dockerfile (增强版)
FROM ubuntu:22.04

# 安装基础工具 (对齐 Docker Gitspace)
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    jq \
    sudo \
    openssh-server \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 复制脚本 (来自 Docker Gitspace)
COPY scripts/docker-gitspace/ /usr/local/gitspace/scripts/common/
COPY scripts/detect-devcontainer-user.sh /usr/local/gitspace/scripts/
COPY scripts/create-user-dynamic.sh /usr/local/gitspace/scripts/

# 设置权限
RUN chmod +x /usr/local/gitspace/scripts/**/*.sh

# 创建默认用户
RUN groupadd -g 1000 vscode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash vscode && \
    echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode

WORKDIR /home/vscode
```

### Phase 3: 创建预装 IDE 的镜像 🔄

**目标**: 创建包含 IDE 的完整镜像

```dockerfile
# vscode/Dockerfile (新增)
FROM gitness/gitspace-base:latest

ARG CODE_SERVER_VERSION=4.23.1

# 预装 code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=${CODE_SERVER_VERSION}

# 预装常用扩展
COPY extensions.txt /tmp/extensions.txt
RUN while read ext; do \
      code-server --install-extension "$ext" --force; \
    done < /tmp/extensions.txt || true

# 复制 IDE 脚本
COPY init-vscode.sh /usr/local/bin/gitspace-init.sh
COPY install-vscode-server.sh /usr/local/gitspace/scripts/vscode/
COPY configure-vscode.sh /usr/local/gitspace/scripts/vscode/

RUN chmod +x /usr/local/bin/gitspace-init.sh

USER vscode
WORKDIR /home/vscode

CMD ["/usr/local/bin/gitspace-init.sh"]
```

### Phase 4: 更新 K8s 部署配置 🔄

**目标**: K8s 使用新的预装镜像

```yaml
# examples/gitspace-vscode.yaml (更新镜像)
initContainers:
- name: gitspace-init
  image: gitness/gitspace:vscode-4.23.1  # 使用预装镜像
  # ... 其他配置

containers:
- name: vscode-ide
  image: gitness/gitspace:vscode-4.23.1  # 使用预装镜像
  # ... 其他配置
```

### Phase 5: 验证开箱即用 ✅

**测试清单**:
- [ ] 镜像构建成功
- [ ] 镜像包含 code-server
- [ ] K8s 部署无需下载 IDE
- [ ] 启动时间 < 60 秒
- [ ] 持久化正常工作
- [ ] Docker 和 K8s 行为一致

---

## 构建和发布流程

### 构建命令

```bash
# 构建所有镜像
make build-all

# 构建特定 IDE
make build-base
make build-vscode
make build-cursor

# 推送镜像
make push-all

# 打标签
make tag VERSION=1.0.0
```

### Makefile 示例

```makefile
REGISTRY ?= gitness
VERSION ?= latest

.PHONY: build-base
build-base:
	docker build -t $(REGISTRY)/gitspace-base:$(VERSION) base/

.PHONY: build-vscode
build-vscode: build-base
	docker build -t $(REGISTRY)/gitspace:vscode-$(VERSION) vscode/

.PHONY: build-all
build-all: build-base build-vscode build-cursor build-jetbrains

.PHONY: push-all
push-all:
	docker push $(REGISTRY)/gitspace-base:$(VERSION)
	docker push $(REGISTRY)/gitspace:vscode-$(VERSION)
	docker push $(REGISTRY)/gitspace:cursor-$(VERSION)
	docker push $(REGISTRY)/gitspace:jetbrains-$(VERSION)
```

---

## 镜像大小优化

### 分层优化

| 层 | 大小 | 内容 |
|---|------|------|
| Base | ~200MB | Ubuntu + 基础工具 + 脚本 |
| VS Code | ~300MB | code-server + 常用扩展 |
| **总计** | **~500MB** | 完整 VS Code Gitspace 镜像 |

### 优化策略

1. **使用 Alpine** (可选)
   - 基础镜像从 200MB → 50MB
   - 需要验证兼容性

2. **多阶段构建**
   - 构建阶段安装工具
   - 运行阶段只保留必要文件

3. **扩展按需安装**
   - 镜像只预装核心扩展
   - 用户扩展按需安装 (持久化)

---

## 用户体验对比

### 改造前 (当前)

```
用户部署 K8s Gitspace
  ↓
Pod 启动
  ↓
InitContainer 克隆代码
  ↓
主容器启动
  ↓
⏳ 下载 code-server (~200MB, 1-2分钟)
  ↓
⏳ 安装 code-server
  ↓
⏳ 安装扩展
  ↓
✅ 启动完成

⏱️ 总耗时: 3-5 分钟
```

### 改造后 (目标)

```
用户部署 K8s Gitspace
  ↓
Pod 启动 (使用预装镜像)
  ↓
InitContainer 克隆代码
  ↓
主容器启动
  ↓
✅ code-server 已存在，直接启动
  ↓
✅ 启动完成

⏱️ 总耗时: 30-60 秒

提升: 5-10 倍启动速度! 🚀
```

---

## 与 Docker Gitspace 的一致性

### 对比矩阵

| 特性 | Docker Gitspace | K8s Runtime (当前) | K8s Runtime (目标) |
|------|----------------|-------------------|-------------------|
| **镜像预装 IDE** | ✅ 是 | ❌ 否 | ✅ 是 |
| **脚本来源** | 内置 Go 模板 | 自定义脚本 | Docker Gitspace 脚本 |
| **持久化位置** | `/home/{user}` | `/workspaces` | `/home/{user}` ✅ |
| **启动时间** | 30-60秒 | 3-5分钟 | 30-60秒 ✅ |
| **用户检测** | 动态 | 固定 | 动态 ✅ |
| **devcontainer.json** | 支持 | 部分 | 完全支持 ✅ |

---

## 后续增强

### 1. 支持更多 IDE

- [ ] Cursor
- [ ] JetBrains (IntelliJ, PyCharm, GoLand)
- [ ] Windsurf

### 2. 扩展预装管理

```yaml
# vscode/extensions.yaml
extensions:
  essential:  # 必装扩展
    - dbaeumer.vscode-eslint
    - esbenp.prettier-vscode
  recommended:  # 推荐扩展
    - golang.go
    - ms-python.python
  optional:  # 可选扩展
    - github.copilot
```

### 3. 多架构支持

```bash
# 构建 amd64 和 arm64
docker buildx build --platform linux/amd64,linux/arm64 \
  -t gitness/gitspace:vscode-latest .
```

---

## 总结

**核心改动**:
1. ✅ 提取 Docker Gitspace 脚本到 `base/scripts/docker-gitspace/`
2. ✅ 创建预装 IDE 的镜像 (开箱即用)
3. ✅ 持久化对齐 (挂载到 HOME)
4. ✅ K8s 配置使用预装镜像

**预期收益**:
- ⚡ 启动速度提升 5-10 倍 (3-5分钟 → 30-60秒)
- ✅ 开箱即用 (无需下载 IDE)
- ✅ 与 Docker Gitspace 100% 一致
- 🎉 用户体验大幅提升

---

**下一步**: 开始实施 Phase 1 - 提取 Docker Gitspace 脚本

**文档版本**: v1.0
**日期**: 2025-11-05
**状态**: 设计完成，待实施
