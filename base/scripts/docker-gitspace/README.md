# Docker Gitspace 脚本集成

## 概述

这些脚本来自 Gitness 项目的 Docker Gitspace 实现,用于初始化和运行云开发环境。

**源路径**: `/Users/ysicing/go/src/github.com/yunop-com/gitness/app/gitspace/orchestrator/utils/script_templates/`

## 脚本映射

### 通用脚本 (Common Scripts)

| 原始文件 | 提取文件 | 用途 |
|---------|---------|------|
| `clone_code.sh` | `clone-code.sh` | 克隆 Git 仓库到 HOME 目录 |
| `setup_git_credentials.sh` | `setup-git-credentials.sh` | 配置 Git 凭证 |
| `manage_user.sh` | `manage-user.sh` | 创建用户和 HOME 目录 |
| `install_git.sh` | `install-git.sh` | 安装 Git |
| `set_env.sh` | `set-env.sh` | 设置环境变量 |
| `setup_ssh_server.sh` | `setup-ssh-server.sh` | 配置 SSH 服务器 |
| `run_ssh_server.sh` | `run-ssh-server.sh` | 启动 SSH 服务器 |
| `supported_os_distribution.sh` | `supported-os-distribution.sh` | 检测操作系统 |

### IDE 专用脚本

详见各 IDE 目录的 README:
- `vscode/scripts/README.md` - VS Code 脚本
- `cursor/scripts/README.md` - Cursor 脚本
- `jetbrains/scripts/README.md` - JetBrains 脚本

## 关键设计特点

### 1. Go Template 变量

Docker Gitspace 使用 Go template 语法注入变量:

```go
// 示例变量
{{ .RepoURL }}      // 仓库 URL
{{ .Branch }}       // 分支名
{{ .RepoName }}     // 仓库名称
{{ .Username }}     // 用户名
{{ .HomeDir }}      // HOME 目录
{{ .Port }}         // IDE 端口
{{ .ProxyURI }}     // 代理 URI
```

### 2. HOME 目录持久化

**关键发现**: Docker Gitspace 将所有内容存储在 `$HOME` 目录:

```bash
# 克隆到 HOME
git clone "$repo_url" "$HOME/$repo_name"

# 配置在 HOME
config_dir="$HOME/.config/code-server"

# 日志在 HOME
nohup code-server > "$HOME/code-server.log"
```

**与 K8s Runtime 对齐**:
- ✅ K8s 也应挂载 PVC 到 `/home/{username}`
- ✅ 确保所有数据持久化 (代码、配置、IDE 数据)
- ✅ 符号链接 `/workspaces -> /home/{username}` 用于向后兼容

### 3. 用户管理

`manage-user.sh` 处理:
- 创建用户 HOME 目录
- 设置正确的权限 (755 for HOME, 700 for .ssh)
- 配置访问方式 (SSH key 或密码)

**K8s 适配**:
- InitContainer 应使用此脚本创建用户
- 确保 UID/GID 与 PVC 权限匹配

### 4. devcontainer.json 创建

`clone-code.sh` 会自动创建默认 devcontainer.json:

```json
{
    "image": "$image"
}
```

**K8s 增强**:
- 可以在 InitContainer 中解析 devcontainer.json
- 动态调整用户配置

## K8s Runtime 集成策略

### Phase 1: 脚本标准化 ✅

- [x] 提取所有脚本到 gitspace-runtime
- [x] 重命名为 kebab-case
- [ ] 创建非模板版本 (用于 K8s)

### Phase 2: 创建镜像

**基础镜像** (`base/Dockerfile`):
```dockerfile
FROM ubuntu:22.04

# 安装基础工具
RUN apt-get update && apt-get install -y \
    git curl wget jq sudo openssh-server

# 复制 Docker Gitspace 脚本
COPY scripts/docker-gitspace/ /usr/local/gitspace/scripts/common/

# 设置权限
RUN chmod +x /usr/local/gitspace/scripts/**/*.sh
```

**IDE 镜像** (`vscode/Dockerfile`):
```dockerfile
FROM gitness/gitspace-base:latest

# 预装 code-server (避免运行时下载!)
ARG CODE_SERVER_VERSION=4.23.1
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=${CODE_SERVER_VERSION}

# 复制 IDE 脚本
COPY scripts/ /usr/local/gitspace/scripts/vscode/
```

### Phase 3: K8s 部署

```yaml
initContainers:
- name: gitspace-init
  image: gitness/gitspace:vscode-latest  # 预装 IDE!
  env:
  - name: REPO_URL
    value: "https://github.com/example/repo.git"
  command:
  - /bin/bash
  - -c
  - |
    # 使用 Docker Gitspace 脚本
    source /usr/local/gitspace/scripts/common/clone-code.sh
    # 脚本已经在镜像中,无需下载!

containers:
- name: vscode-ide
  image: gitness/gitspace:vscode-latest  # 同一镜像
  command:
  - /bin/bash
  - -c
  - |
    # code-server 已预装,直接启动!
    code-server --disable-workspace-trust "$HOME/$REPO_NAME"
```

## 模板变量 vs 环境变量映射

| Go Template | K8s 环境变量 | 示例值 |
|------------|-------------|--------|
| `{{ .RepoURL }}` | `$REPO_URL` | `https://github.com/example/repo.git` |
| `{{ .Branch }}` | `$BRANCH` | `main` |
| `{{ .RepoName }}` | `$REPO_NAME` | `my-repo` |
| `{{ .Username }}` | `$USERNAME` | `vscode` |
| `{{ .HomeDir }}` | `$HOME` | `/home/vscode` |
| `{{ .Port }}` | `$IDE_PORT` | `8089` |
| `{{ .ProxyURI }}` | `$VSCODE_PROXY_URI` | `https://proxy.example.com` |

## 下一步

1. **创建非模板脚本版本**: 将 Go template 变量替换为环境变量引用
2. **构建基础镜像**: 包含所有脚本和基础工具
3. **构建 IDE 镜像**: 预装 code-server, cursor, 等
4. **验证开箱即用**: 确保 K8s 部署无需下载 IDE

## 参考文档

- [统一架构设计](../../../docs/unified-runtime-design.md)
- [实施完成报告](../../../docs/implementation-completion-report.md)
- [一致性验证脚本](../../../verify-docker-k8s-consistency.sh)
