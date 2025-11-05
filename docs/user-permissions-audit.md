# Gitspace 用户权限一致性审计

## 执行摘要

对比 Docker Gitspace 实现和 K8s Runtime 实现，发现以下关键不一致性需要标准化。

---

## 当前状态分析

### Docker Gitspace 实现 (Gitness 后端)

#### 核心概念
从 `app/gitspace/orchestrator/devcontainer/exec.go:42-51` 可见:

```go
type Exec struct {
    ContainerName     string
    DockerClient      *client.Client
    DefaultWorkingDir string      // ← 关键：工作目录
    RemoteUser        string       // ← 关键：远程用户
    AccessKey         string
    AccessType        enum.GitspaceAccessType
    Arch              string
    OS                string
}
```

#### 用户模型
- **ContainerUser**: 容器内的实际运行用户 (从 devcontainer.json 的 `containerUser` 读取)
- **RemoteUser**: IDE 连接使用的用户 (从 devcontainer.json 的 `remoteUser` 读取)
- **默认值**: 如果未指定，两者都默认为 `vscode` 或从基础镜像检测

#### 目录结构
- **WorkspaceMount**: `/workspaces` (Docker 标准)
- **RepoPath**: `/workspaces/{repo-name}`
- **DefaultWorkingDir**: 通常是 `RemoteUser` 的 HOME 目录

#### 权限处理
从 `app/gitspace/orchestrator/utils/user.go:25-51` 可见:
- 使用 `ManageUser()` 函数设置用户目录和凭证
- 在容器启动后通过 `exec` 命令配置
- 支持动态用户创建

---

### K8s Runtime 实现 (gitspace-runtime)

#### 当前配置

**base/Dockerfile:50-67**
```dockerfile
# 创建 vscode 用户（UID/GID: 1000）
RUN if ! id -u vscode > /dev/null 2>&1; then \
        groupadd -g 1000 vscode \
        && useradd -m -u 1000 -g 1000 -s /bin/bash vscode \
        && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers; \
    fi

# 创建标准目录结构
RUN mkdir -p /workspace \
    /home/vscode/.config \
    /home/vscode/.local \
    /shared \
    && chown -R vscode:vscode /workspace /home/vscode /shared

USER vscode
WORKDIR /workspace
```

**examples/gitspace-vscode.yaml:40-43**
```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
```

---

## 关键不一致性

### 🔴 1. 工作目录路径

| 实现 | 路径 | 说明 |
|------|------|------|
| **Docker Gitspace** | `/workspaces` | VS Code Dev Container 标准 |
| **K8s Runtime** | `/workspace` | 少了一个 's' ❌ |

**影响**:
- devcontainer.json 中的 `workspaceFolder` 默认为 `/workspaces`
- 路径不一致会导致 IDE 配置失效
- 扩展和调试配置可能失败

### 🔴 2. 用户模型缺失

| 概念 | Docker Gitspace | K8s Runtime |
|------|----------------|-------------|
| **ContainerUser** | ✅ 支持动态检测 | ❌ 硬编码 vscode |
| **RemoteUser** | ✅ 从 devcontainer 读取 | ❌ 未实现 |
| **用户创建** | ✅ 动态创建 | ❌ 构建时固定 |

**影响**:
- 无法支持需要 root 用户的镜像
- 无法支持自定义用户名
- 与 devcontainer.json 配置冲突

### 🔴 3. HOME 目录处理

| 实现 | HOME 目录 | 说明 |
|------|-----------|------|
| **Docker Gitspace** | 动态 (`/home/{remoteUser}`) | 根据用户名确定 |
| **K8s Runtime** | 固定 (`/home/vscode`) | 硬编码 ❌ |

**影响**:
- 不同用户的配置文件可能冲突
- SSH 配置路径不正确

### 🔴 4. 权限修复时机

| 实现 | 时机 | 方法 |
|------|------|------|
| **Docker Gitspace** | 容器运行后 | 通过 `exec` 动态配置 |
| **K8s Runtime** | initContainer | 在主容器启动前 ✅ 更好 |

K8s Runtime 的方式实际上更好，但实现不完整。

### 🔴 5. UID/GID 固定值

| 实现 | UID | GID | 可配置性 |
|------|-----|-----|---------|
| **Docker Gitspace** | 动态检测 | 动态检测 | ✅ 高 |
| **K8s Runtime** | 1000 (硬编码) | 1000 (硬编码) | ❌ 低 |

**影响**:
- 无法使用需要特定 UID 的镜像
- NFS 挂载时可能遇到权限问题

---

## 标准化方案

### 阶段 1: 目录路径标准化 (优先级: 🔴 高)

#### 1.1 修改基础目录为 `/workspaces`

**修改文件**: `base/Dockerfile`
```diff
- RUN mkdir -p /workspace \
+ RUN mkdir -p /workspaces \
      /home/vscode/.config \
      /home/vscode/.local \
      /shared \
-     && chown -R vscode:vscode /workspace /home/vscode /shared
+     && chown -R vscode:vscode /workspaces /home/vscode /shared

- USER vscode
- WORKDIR /workspace
+ USER vscode
+ WORKDIR /workspaces
```

**修改文件**: `base/scripts/clone-repository.sh`
```diff
- local workspace_dir="${WORKSPACE_DIR:-/workspace}"
+ local workspace_dir="${WORKSPACE_DIR:-/workspaces}"
```

**修改文件**: `examples/gitspace-vscode.yaml`
```diff
  env:
  - name: WORKSPACE_DIR
-   value: "/workspace"
+   value: "/workspaces"
```

#### 1.2 添加向后兼容性

为了不破坏现有部署，添加软链接:
```dockerfile
RUN ln -s /workspaces /workspace
```

### 阶段 2: 用户模型标准化 (优先级: 🟡 中)

#### 2.1 支持动态用户检测

**新增文件**: `base/scripts/detect-user.sh`
```bash
#!/bin/bash
# 检测容器用户配置

detect_container_user() {
    local container_user="${CONTAINER_USER:-}"
    local remote_user="${REMOTE_USER:-}"

    # 优先级: 环境变量 > devcontainer.json > 默认值
    if [ -z "$container_user" ]; then
        # 从 devcontainer.json 读取
        if [ -f "/workspaces/.devcontainer/devcontainer.json" ]; then
            container_user=$(jq -r '.containerUser // "vscode"' /workspaces/.devcontainer/devcontainer.json)
        else
            container_user="vscode"
        fi
    fi

    if [ -z "$remote_user" ]; then
        if [ -f "/workspaces/.devcontainer/devcontainer.json" ]; then
            remote_user=$(jq -r '.remoteUser // "vscode"' /workspaces/.devcontainer/devcontainer.json)
        else
            remote_user="$container_user"
        fi
    fi

    echo "CONTAINER_USER=$container_user"
    echo "REMOTE_USER=$remote_user"
}
```

#### 2.2 动态用户创建

**修改文件**: `base/Dockerfile`
```dockerfile
# 不再硬编码创建用户，而是准备好环境
RUN apt-get update && apt-get install -y \
    sudo \
    && apt-get clean

# 创建用户管理脚本
COPY base/scripts/create-user-if-needed.sh /usr/local/gitspace/scripts/common/
RUN chmod +x /usr/local/gitspace/scripts/common/*.sh
```

**新增文件**: `base/scripts/create-user-if-needed.sh`
```bash
#!/bin/bash
# 动态创建用户（如果不存在）

create_user_if_needed() {
    local username="${1:-vscode}"
    local uid="${2:-1000}"
    local gid="${3:-1000}"

    if ! id -u "$username" > /dev/null 2>&1; then
        log_info "Creating user: $username (UID: $uid, GID: $gid)"
        groupadd -g "$gid" "$username" 2>/dev/null || true
        useradd -m -u "$uid" -g "$gid" -s /bin/bash "$username"
        echo "$username ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        log_info "User $username created successfully"
    else
        log_info "User $username already exists"
    fi
}
```

### 阶段 3: 配置参数化 (优先级: 🟡 中)

#### 3.1 环境变量标准化

**所有镜像支持以下环境变量**:

```yaml
env:
# 用户配置
- name: CONTAINER_USER
  value: "vscode"           # 容器运行用户
- name: REMOTE_USER
  value: "vscode"           # IDE 连接用户
- name: USER_UID
  value: "1000"             # 用户 UID
- name: USER_GID
  value: "1000"             # 用户 GID

# 目录配置
- name: WORKSPACE_DIR
  value: "/workspaces"      # 工作区根目录
- name: REPO_NAME
  value: "my-repo"
- name: HOME
  value: "/home/vscode"     # HOME 目录

# Git 配置
- name: REPO_URL
  value: "https://..."
- name: BRANCH
  value: "main"
- name: GIT_USERNAME
  value: ""
- name: GIT_PASSWORD
  value: ""
```

### 阶段 4: securityContext 标准化 (优先级: 🔴 高)

#### 4.1 使用环境变量驱动

**修改文件**: `examples/gitspace-vscode.yaml`
```yaml
spec:
  securityContext:
    # 使用环境变量配置的 UID/GID
    runAsUser: 1000    # 可通过 ConfigMap 配置
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch  # K8s 1.20+ 优化性能

  initContainers:
  - name: gitspace-init
    image: gitness/gitspace:vscode-latest
    command: ["/usr/local/bin/gitspace-init.sh"]
    env:
    - name: USER_UID
      value: "1000"
    - name: USER_GID
      value: "1000"
    - name: CONTAINER_USER
      value: "vscode"
    - name: REMOTE_USER
      value: "vscode"
    # ... 其他配置
```

---

## 实施计划

### 第 1 周: 目录路径标准化
- [ ] 修改 base/Dockerfile 工作目录为 `/workspaces`
- [ ] 更新所有脚本中的路径引用
- [ ] 添加向后兼容软链接
- [ ] 更新示例 YAML 文件
- [ ] 测试所有 IDE (vscode/cursor/jetbrains)

### 第 2 周: 用户模型实现
- [ ] 实现 `detect-user.sh` 脚本
- [ ] 实现 `create-user-if-needed.sh` 脚本
- [ ] 修改 init 脚本集成用户检测
- [ ] 测试动态用户创建

### 第 3 周: 参数化和文档
- [ ] 标准化环境变量
- [ ] 创建配置模板
- [ ] 编写迁移指南
- [ ] 更新 README 和文档

### 第 4 周: 测试和验证
- [ ] 单元测试
- [ ] 集成测试
- [ ] 性能测试
- [ ] 兼容性测试

---

## 验证清单

### 功能验证
- [ ] devcontainer.json 的 `containerUser` 配置生效
- [ ] devcontainer.json 的 `remoteUser` 配置生效
- [ ] 自定义 UID/GID 可以正常工作
- [ ] `/workspaces` 路径权限正确
- [ ] HOME 目录自动创建并设置权限

### 兼容性验证
- [ ] Docker 环境运行正常
- [ ] Kubernetes 环境运行正常
- [ ] 支持 hostPath 存储类
- [ ] 支持 NFS 存储类
- [ ] 支持云存储 (EBS/GCE PD/Azure Disk)

### 安全验证
- [ ] 非 root 用户默认运行
- [ ] sudo 权限配置正确
- [ ] 文件权限最小化
- [ ] securityContext 配置合规

---

## 风险和缓解

### 风险 1: 破坏现有部署
**缓解**:
- 添加向后兼容软链接 `/workspace -> /workspaces`
- 发布前通知用户
- 提供迁移脚本

### 风险 2: 性能影响
**缓解**:
- 使用 `fsGroupChangePolicy: OnRootMismatch` 减少权限修复时间
- 缓存用户检测结果

### 风险 3: 测试覆盖不足
**缓解**:
- 增加自动化测试
- 多存储后端测试
- 社区 Beta 测试

---

## 参考文档

### Gitness Docker 实现
- `app/gitspace/orchestrator/devcontainer/exec.go:42-51` - Exec 结构
- `app/gitspace/orchestrator/utils/user.go:25-51` - 用户管理
- `app/gitspace/orchestrator/container/devcontainer_config_utils.go` - 配置解析

### VS Code Dev Container 规范
- [Dev Container Specification](https://containers.dev/implementors/json_reference/)
- `remoteUser`: 默认连接用户
- `containerUser`: 容器运行用户
- `workspaceMount`: 工作区挂载路径
- `workspaceFolder`: 工作目录路径

### Kubernetes 最佳实践
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
