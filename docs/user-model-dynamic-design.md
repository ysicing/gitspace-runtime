# 用户模型动态化设计文档

## 概述

本文档描述统一的用户模型,使 Docker 和 Kubernetes Gitspace Runtime 支持动态用户配置,完全兼容 devcontainer.json 规范。

---

## 当前状态分析

### Docker Gitspace 实现 ✅

**优势**:
1. 完整支持 `containerUser` 和 `remoteUser`
2. 从多个来源动态检测用户:
   - runArgs (最高优先级)
   - devcontainer.json (`containerUser` / `remoteUser`)
   - 镜像元数据
   - 镜像默认用户
   - 系统默认值

**实现位置**:
- `app/gitspace/orchestrator/container/util.go:45-60` - GetContainerUser
- `app/gitspace/orchestrator/container/util.go:45-50` - GetUserHomeDir
- `app/gitspace/orchestrator/container/kubernetes_orchestrator.go:1764-1791` - getContainerUser
- `app/gitspace/orchestrator/container/kubernetes_orchestrator.go:1794-1816` - getRemoteUser

### K8s Runtime 实现 ❌

**问题**:
1. 用户硬编码: 总是 `vscode`
2. UID/GID 固定: 1000:1000
3. 不读取 devcontainer.json
4. 无法支持 root 用户或自定义用户

---

## 统一用户模型设计

### 核心概念

```
┌─────────────────────────────────────────────────────────────────┐
│                         用户模型层次                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. containerUser  (容器运行用户)                                │
│     - 容器内实际运行进程的用户                                    │
│     - 决定文件权限和进程所有权                                    │
│     - 在 Docker 中对应 `--user` 参数                            │
│     - 在 K8s 中对应 securityContext.runAsUser                   │
│                                                                   │
│  2. remoteUser     (远程连接用户)                                │
│     - IDE 连接到容器时使用的用户                                  │
│     - 决定 HOME 目录和工作目录                                    │
│     - 决定 SSH 连接的用户                                        │
│     - 通常与 containerUser 相同,但可以不同                       │
│                                                                   │
│  3. UID/GID        (用户/组 ID)                                  │
│     - 数字形式的用户标识                                          │
│     - 解决文件权限映射问题                                        │
│     - 对于 K8s PVC 至关重要                                      │
│                                                                   │
│  4. HOME 目录      (用户主目录)                                   │
│     - 基于 remoteUser 动态计算                                   │
│     - root: /root                                               │
│     - 其他: /home/{username}                                     │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 用户检测优先级 (与 Docker 一致)

```
优先级从高到低:
1. 环境变量 CONTAINER_USER / REMOTE_USER (运行时覆盖)
2. devcontainer.json 的 containerUser / remoteUser
3. 镜像元数据 (LABEL devcontainer.containerUser)
4. 镜像默认用户 (docker inspect 的 User 字段)
5. 系统默认值 (vscode)
```

### UID/GID 解析规则

```go
// 用户字符串格式支持:
// 1. "username"         -> UID 从镜像或创建用户时分配
// 2. "1000"             -> UID 1000, 用户名从 /etc/passwd 查找或创建
// 3. "username:groupname" -> 解析为 UID:GID
// 4. "1000:1000"        -> 直接使用 UID:GID
```

---

## 实施方案

### 阶段 1: 脚本层实现 (K8s Runtime)

#### 1.1 用户检测脚本

**新增文件**: `base/scripts/detect-devcontainer-user.sh`

```bash
#!/bin/bash
# 从 devcontainer.json 检测用户配置
# 返回: CONTAINER_USER, REMOTE_USER, USER_UID, USER_GID, HOME_DIR

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

detect_devcontainer_user() {
    local repo_dir="${1:-/workspaces}"
    local devcontainer_file="$repo_dir/.devcontainer/devcontainer.json"

    # 默认值
    local container_user="${CONTAINER_USER:-vscode}"
    local remote_user="${REMOTE_USER:-}"
    local user_uid="${USER_UID:-1000}"
    local user_gid="${USER_GID:-1000}"

    # 如果 devcontainer.json 存在,读取配置
    if [ -f "$devcontainer_file" ]; then
        log_info "Found devcontainer.json, parsing user configuration..."

        # 解析 containerUser
        local container_user_from_file
        container_user_from_file=$(jq -r '.containerUser // empty' "$devcontainer_file" 2>/dev/null || echo "")
        if [ -n "$container_user_from_file" ]; then
            container_user="$container_user_from_file"
            log_info "Using containerUser from devcontainer.json: $container_user"
        fi

        # 解析 remoteUser
        local remote_user_from_file
        remote_user_from_file=$(jq -r '.remoteUser // empty' "$devcontainer_file" 2>/dev/null || echo "")
        if [ -n "$remote_user_from_file" ]; then
            remote_user="$remote_user_from_file"
            log_info "Using remoteUser from devcontainer.json: $remote_user"
        fi
    else
        log_info "No devcontainer.json found, using defaults"
    fi

    # 如果 remoteUser 未设置,使用 containerUser
    if [ -z "$remote_user" ]; then
        remote_user="$container_user"
    fi

    # 解析用户字符串获取 UID/GID
    parse_user_string "$container_user" "$user_uid" "$user_gid"

    # 计算 HOME 目录
    local home_dir
    if [ "$remote_user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$remote_user"
    fi

    # 输出结果 (用于 source)
    echo "export CONTAINER_USER='$container_user'"
    echo "export REMOTE_USER='$remote_user'"
    echo "export USER_UID='$user_uid'"
    echo "export USER_GID='$user_gid'"
    echo "export HOME_DIR='$home_dir'"

    log_info "User detection completed:"
    log_info "  CONTAINER_USER=$container_user"
    log_info "  REMOTE_USER=$remote_user"
    log_info "  USER_UID=$user_uid"
    log_info "  USER_GID=$user_gid"
    log_info "  HOME_DIR=$home_dir"
}

# 解析用户字符串 (username, uid, username:gid, uid:gid)
parse_user_string() {
    local user_str="$1"
    local default_uid="$2"
    local default_gid="$3"

    # 检查是否包含 :
    if [[ "$user_str" == *:* ]]; then
        # 格式: username:groupname 或 uid:gid
        IFS=':' read -r user_part group_part <<< "$user_str"

        # 检查是否是纯数字
        if [[ "$user_part" =~ ^[0-9]+$ ]]; then
            user_uid="$user_part"
        else
            # 从系统查找用户 UID
            user_uid=$(id -u "$user_part" 2>/dev/null || echo "$default_uid")
        fi

        if [[ "$group_part" =~ ^[0-9]+$ ]]; then
            user_gid="$group_part"
        else
            # 从系统查找组 GID
            user_gid=$(getent group "$group_part" 2>/dev/null | cut -d: -f3 || echo "$default_gid")
        fi
    else
        # 格式: username 或 uid
        if [[ "$user_str" =~ ^[0-9]+$ ]]; then
            user_uid="$user_str"
            user_gid="$user_str"
        else
            # 尝试从系统查找
            if id "$user_str" >/dev/null 2>&1; then
                user_uid=$(id -u "$user_str")
                user_gid=$(id -g "$user_str")
            else
                user_uid="$default_uid"
                user_gid="$default_gid"
            fi
        fi
    fi
}

# 如果直接执行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    detect_devcontainer_user "$@"
fi
```

#### 1.2 动态用户创建脚本

**新增文件**: `base/scripts/create-user-dynamic.sh`

```bash
#!/bin/bash
# 动态创建或更新用户

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

create_or_update_user() {
    local username="${1:-vscode}"
    local uid="${2:-1000}"
    local gid="${3:-1000}"
    local home_dir="${4:-/home/$username}"

    log_info "=========================================="
    log_info "Configuring user: $username (UID: $uid, GID: $gid)"
    log_info "=========================================="

    # 特殊处理: root 用户不需要创建
    if [ "$username" = "root" ]; then
        log_info "User is root, skipping user creation"
        return 0
    fi

    # 检查用户是否存在
    if id "$username" >/dev/null 2>&1; then
        local existing_uid
        existing_uid=$(id -u "$username")
        local existing_gid
        existing_gid=$(id -g "$username")

        if [ "$existing_uid" = "$uid" ] && [ "$existing_gid" = "$gid" ]; then
            log_info "User $username already exists with correct UID/GID"
        else
            log_info "User $username exists but with different UID/GID"
            log_info "  Existing: UID=$existing_uid, GID=$existing_gid"
            log_info "  Expected: UID=$uid, GID=$gid"
            log_info "  Updating user UID/GID..."

            # 更新 UID/GID (需要 root 权限)
            sudo usermod -u "$uid" "$username" 2>/dev/null || true
            sudo groupmod -g "$gid" "$username" 2>/dev/null || true
        fi
    else
        log_info "User $username does not exist, creating..."

        # 检查组是否存在
        if ! getent group "$username" >/dev/null 2>&1; then
            sudo groupadd -g "$gid" "$username" 2>/dev/null || true
        fi

        # 创建用户
        sudo useradd -m -u "$uid" -g "$gid" -s /bin/bash -d "$home_dir" "$username"

        # 添加 sudo 权限
        echo "$username ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/$username > /dev/null
        sudo chmod 0440 /etc/sudoers.d/$username

        log_info "User $username created successfully"
    fi

    # 确保 HOME 目录存在且权限正确
    if [ ! -d "$home_dir" ]; then
        log_info "Creating HOME directory: $home_dir"
        sudo mkdir -p "$home_dir"
    fi

    log_info "Setting permissions on HOME directory..."
    sudo chown -R "$uid:$gid" "$home_dir"

    # 创建常用配置目录
    for dir in .config .local .cache; do
        if [ ! -d "$home_dir/$dir" ]; then
            sudo mkdir -p "$home_dir/$dir"
            sudo chown "$uid:$gid" "$home_dir/$dir"
        fi
    done

    log_info "User configuration completed"
}

# 如果直接执行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    create_or_update_user "$@"
fi
```

#### 1.3 集成到 init 脚本

**修改文件**: `vscode/init-vscode.sh`

```bash
#!/bin/bash
# Gitspace VSCode 初始化脚本
# 执行顺序: 检测用户 → Git凭证 → 创建用户 → 克隆代码 → 安装VSCode → 配置VSCode → 生成启动脚本

set -euo pipefail

# ========================================
# 环境变量
# ========================================
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspaces}"
REPO_NAME="${REPO_NAME:-}"
REPO_DIR="$WORKSPACE_DIR/$REPO_NAME"
IDE_PORT="${IDE_PORT:-8089}"
GITSPACE_IDENTIFIER="${GITSPACE_IDENTIFIER:-gitspace}"

# 用户配置 (可被 devcontainer.json 覆盖)
CONTAINER_USER="${CONTAINER_USER:-vscode}"
REMOTE_USER="${REMOTE_USER:-vscode}"
USER_UID="${USER_UID:-1000}"
USER_GID="${USER_GID:-1000}"
HOME_DIR="${HOME_DIR:-/home/vscode}"

# ========================================
# 日志函数
# ========================================
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

# ========================================
# 主函数
# ========================================
main() {
    log_info "=========================================="
    log_info "Gitspace VSCode Initialization Started"
    log_info "Gitspace ID: $GITSPACE_IDENTIFIER"
    log_info "=========================================="

    # 第0步: 设置 Git 凭证 (在克隆前必须完成)
    log_info "Step 0/6: Setting up Git credentials..."
    source /usr/local/gitspace/scripts/common/setup-git-credentials.sh
    setup_git_credentials

    # 第1步: 克隆代码仓库 (需要 Git 凭证)
    log_info "Step 1/6: Cloning repository..."
    source /usr/local/gitspace/scripts/common/clone-repository.sh
    clone_repository

    # 第2步: 检测用户配置 (从 devcontainer.json)
    log_info "Step 2/6: Detecting user configuration from devcontainer.json..."
    if [ -d "$REPO_DIR" ]; then
        source /usr/local/gitspace/scripts/common/detect-devcontainer-user.sh
        eval "$(detect_devcontainer_user "$REPO_DIR")"
    else
        log_info "Repository not found, using default user configuration"
    fi

    # 第3步: 创建或更新用户
    log_info "Step 3/6: Creating/updating user..."
    source /usr/local/gitspace/scripts/common/create-user-dynamic.sh
    create_or_update_user "$CONTAINER_USER" "$USER_UID" "$USER_GID" "$HOME_DIR"

    # 第4步: 安装 VSCode Server
    log_info "Step 4/6: Installing VSCode Server..."
    source /usr/local/gitspace/scripts/vscode/install-vscode-server.sh
    install_vscode_server

    # 第5步: 配置 VSCode
    log_info "Step 5/6: Configuring VSCode..."
    source /usr/local/gitspace/scripts/vscode/configure-vscode.sh
    configure_vscode

    # 第6步: 生成启动脚本
    log_info "Step 6/6: Generating startup script..."
    generate_start_script

    log_success "=========================================="
    log_success "Gitspace VSCode Initialization Completed"
    log_success "=========================================="
}

# ========================================
# 生成启动脚本
# ========================================
generate_start_script() {
    cat > /shared/start.sh <<EOF
#!/bin/bash
set -e

# 加载环境变量
export HOME="$HOME_DIR"
export USER="$REMOTE_USER"
export WORKSPACE_DIR="$WORKSPACE_DIR"
export REPO_NAME="$REPO_NAME"
export IDE_PORT="$IDE_PORT"

log_info() { echo "[INFO] \$(date '+%Y-%m-%d %H:%M:%S') - \$*"; }

log_info "Starting VSCode Server..."
log_info "User: $REMOTE_USER (UID: $USER_UID)"
log_info "Workspace: $WORKSPACE_DIR/$REPO_NAME"
log_info "Port: $IDE_PORT"

# 进入工作目录
cd "$WORKSPACE_DIR/$REPO_NAME" || cd "$HOME_DIR"

# 配置目录
config_dir="$HOME_DIR/.config/code-server"
mkdir -p "\$config_dir"

# 创建配置文件
cat > "\$config_dir/config.yaml" <<CONFIG_EOF
bind-addr: 0.0.0.0:$IDE_PORT
auth: none
cert: false
CONFIG_EOF

# 启动 code-server (以指定用户运行)
log_info "Launching code-server as user $REMOTE_USER..."
exec code-server --disable-workspace-trust "$WORKSPACE_DIR/$REPO_NAME"
EOF

    chmod +x /shared/start.sh
    log_info "Startup script created at /shared/start.sh"
}

# 执行主函数
main
```

### 阶段 2: K8s securityContext 动态化

#### 2.1 使用 InitContainer 动态生成配置

**修改文件**: `examples/gitspace-vscode.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitspace-vscode
  namespace: gitspace-demo
spec:
  template:
    spec:
      # Pod 级别 securityContext - 使用较宽松的设置
      securityContext:
        fsGroup: 1000  # 默认文件组
        fsGroupChangePolicy: OnRootMismatch

      initContainers:
      # 第一个 init: 检测用户配置
      - name: detect-user
        image: gitness/gitspace:vscode-latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -e
            # 克隆代码
            source /usr/local/gitspace/scripts/common/setup-git-credentials.sh
            setup_git_credentials
            source /usr/local/gitspace/scripts/common/clone-repository.sh
            clone_repository

            # 检测用户
            source /usr/local/gitspace/scripts/common/detect-devcontainer-user.sh
            detect_devcontainer_user "$WORKSPACE_DIR/$REPO_NAME" > /shared/user-config.env

            cat /shared/user-config.env
        env:
        - name: WORKSPACE_DIR
          value: "/workspaces"
        - name: REPO_NAME
          value: "my-repo"
        - name: REPO_URL
          value: "https://github.com/example/my-repo.git"
        - name: GIT_USERNAME
          value: ""
        - name: GIT_PASSWORD
          value: ""
        volumeMounts:
        - name: workspace
          mountPath: /workspaces
        - name: shared
          mountPath: /shared

      # 第二个 init: 创建用户和初始化
      - name: gitspace-init
        image: gitness/gitspace:vscode-latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -e
            # 加载用户配置
            source /shared/user-config.env

            # 创建用户
            source /usr/local/gitspace/scripts/common/create-user-dynamic.sh
            create_or_update_user "$CONTAINER_USER" "$USER_UID" "$USER_GID" "$HOME_DIR"

            # 继续其他初始化
            /usr/local/bin/gitspace-init.sh
        volumeMounts:
        - name: workspace
          mountPath: /workspaces
        - name: shared
          mountPath: /shared
        securityContext:
          runAsUser: 0  # InitContainer 需要 root 权限创建用户

      containers:
      - name: vscode-ide
        image: gitness/gitspace:vscode-latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -e
            # 加载用户配置
            source /shared/user-config.env

            # 切换到目标用户并启动
            exec su - "$REMOTE_USER" -c "/shared/start.sh"
        env:
        - name: WORKSPACE_DIR
          value: "/workspaces"
        - name: REPO_NAME
          value: "my-repo"
        volumeMounts:
        - name: workspace
          mountPath: /workspaces
        - name: shared
          mountPath: /shared
        # 注意: 主容器以 root 启动,但会 su 到目标用户
        securityContext:
          runAsUser: 0
          allowPrivilegeEscalation: true  # su 命令需要
```

---

## 验证测试用例

### 测试用例 1: 默认用户 (vscode)

```yaml
# 不提供 devcontainer.json
# 预期: containerUser=vscode, remoteUser=vscode, UID=1000, GID=1000
```

### 测试用例 2: Root 用户

```json
// .devcontainer/devcontainer.json
{
  "image": "ubuntu:22.04",
  "containerUser": "root",
  "remoteUser": "root"
}
```

预期: containerUser=root, remoteUser=root, HOME=/root

### 测试用例 3: 自定义用户名

```json
{
  "image": "node:18",
  "containerUser": "node",
  "remoteUser": "node"
}
```

预期: 检测 node 用户的 UID/GID 或创建新用户

### 测试用例 4: 显式 UID/GID

```json
{
  "image": "custom:latest",
  "containerUser": "1001:1001",
  "remoteUser": "developer"
}
```

预期: UID=1001, GID=1001, username=developer

### 测试用例 5: containerUser 与 remoteUser 不同

```json
{
  "image": "base:latest",
  "containerUser": "www-data",
  "remoteUser": "developer"
}
```

预期: 进程以 www-data 运行, IDE 连接到 developer

---

## 兼容性矩阵

| 场景 | Docker Gitspace | K8s Runtime (新) | 状态 |
|------|----------------|-----------------|------|
| 默认用户 (vscode) | ✅ | ✅ | 一致 |
| Root 用户 | ✅ | ✅ | 一致 |
| 自定义用户名 | ✅ | ✅ | 一致 |
| 显式 UID/GID | ✅ | ✅ | 一致 |
| devcontainer.json 检测 | ✅ | ✅ | 一致 |
| 镜像元数据检测 | ✅ | ⚠️ 待实现 | 部分 |
| 动态用户创建 | ✅ | ✅ | 一致 |

---

## 实施计划

### Week 1: 脚本实现
- [ ] Day 1-2: 编写 `detect-devcontainer-user.sh`
- [ ] Day 3-4: 编写 `create-user-dynamic.sh`
- [ ] Day 5: 集成到 init 脚本

### Week 2: K8s 集成
- [ ] Day 1-2: 修改 Deployment YAML 模板
- [ ] Day 3-4: 测试不同用户场景
- [ ] Day 5: 文档和示例

### Week 3: 高级功能
- [ ] Day 1-2: 镜像元数据检测
- [ ] Day 3: NFS/共享存储测试
- [ ] Day 4-5: 性能优化

### Week 4: 测试和文档
- [ ] Day 1-2: 全面集成测试
- [ ] Day 3-4: 编写迁移指南
- [ ] Day 5: 代码审查和发布

---

## 安全考虑

### InitContainer 权限

**问题**: InitContainer 需要 root 权限创建用户

**缓解**:
1. InitContainer 仅运行受信脚本
2. 主容器可以切换到非 root 用户
3. 使用 SecurityContext 限制能力

### UID 冲突

**问题**: 多个 Gitspace 使用相同 UID 可能冲突

**缓解**:
1. 使用命名空间隔离
2. PVC 独占,不共享
3. 文档说明最佳实践

### Privilege Escalation

**问题**: `su` 命令需要 `allowPrivilegeEscalation: true`

**缓解**:
1. 仅在需要时使用
2. 限制在容器内部
3. 考虑使用 `gosu` 替代

---

## 参考资料

- [Dev Container Specification - User](https://containers.dev/implementors/json_reference/#general-properties)
- Docker Gitspace: `app/gitspace/orchestrator/container/util.go`
- Kubernetes Security Context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
