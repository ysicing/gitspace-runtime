# K8s Runtime 对齐 Docker Gitspace - 实施方案 (镜像已优化场景)

## 背景说明

**已完成**: 镜像中已预装 VS Code Server, 避免每次下载

**当前目标**: 在镜像已优化的前提下, 确保 Docker 和 K8s 的**用户模型**和**持久化路径**完全一致

---

## 核心一致性要求

### 1. 用户模型一致性

| 维度 | Docker Gitspace | K8s Runtime (目标) |
|------|----------------|-------------------|
| containerUser | 动态检测 (devcontainer.json) | ✅ 需要实现 (已有脚本) |
| remoteUser | 动态检测 (devcontainer.json) | ✅ 需要实现 (已有脚本) |
| UID/GID | 动态解析 (支持 4 种格式) | ✅ 需要实现 (已有脚本) |
| HOME 目录 | `/home/{username}` 或 `/root` | ⚠️ 需要调整 |
| 默认用户 | `vscode` | ✅ 已一致 |

### 2. 持久化路径一致性

| 项目 | Docker Gitspace | K8s Runtime (当前) | K8s Runtime (目标) |
|------|----------------|-------------------|-------------------|
| **卷挂载点** | `/home/{username}` | `/workspaces` | `/home/{username}` |
| **工作目录** | `/home/{username}` | `/workspaces` | `/home/{username}` |
| **代码路径** | `$HOME/{repo}` | `/workspaces/{repo}` | `$HOME/{repo}` |
| **用户配置** | `$HOME/.bashrc` 等 | `/home/vscode/.bashrc` | `$HOME/.bashrc` |
| **IDE 数据** | `$HOME/.vscode-server` | `/home/vscode/.vscode-server` | `$HOME/.vscode-server` |

**关键变化**: 持久化卷从 `/workspaces` 挂载改为 `/home/{username}` 挂载

---

## 为什么需要改为挂载到 HOME?

### 原因 1: Docker Gitspace 的设计

Docker Gitspace 挂载到 HOME 目录的原因:

```go
// app/gitspace/orchestrator/container/embedded_docker_container_orchestrator.go
remoteUserHomeDir := GetUserHomeDir(remoteUser)  // /home/vscode

CreateContainer(
    storage,              // Docker Volume
    remoteUserHomeDir,    // 挂载到 HOME 目录
    mount.TypeVolume,
    // ...
)
```

### 原因 2: 完整的用户环境持久化

**挂载到 HOME** (Docker 方式):
```
/home/vscode/                ← 持久化卷
├── .bashrc                  ← 用户配置 (持久化)
├── .profile                 ← Shell 配置 (持久化)
├── .gitconfig               ← Git 配置 (持久化)
├── .ssh/                    ← SSH 密钥 (持久化)
├── .vscode-server/          ← IDE 数据 (持久化, 即使镜像预装)
│   └── data/                ← 工作区设置、扩展配置
├── .config/                 ← 应用配置 (持久化)
└── my-repo/                 ← 代码 (持久化)
```

**挂载到 /workspaces** (当前方式):
```
/workspaces/                 ← 持久化卷
└── my-repo/                 ← 只有代码持久化

/home/vscode/                ← 容器文件系统 (ephemeral)
├── .bashrc                  ← 每次重启丢失 ❌
├── .gitconfig               ← 每次重启丢失 ❌
├── .ssh/                    ← 每次重启丢失 ❌
└── .vscode-server/data/     ← 工作区设置丢失 ❌
```

### 原因 3: 即使镜像预装了 VS Code Server, 用户数据仍需持久化

**镜像预装的部分** (不需要重复下载):
- ✅ VS Code Server 二进制 (`~/.vscode-server/bin/`)
- ✅ 基础扩展

**用户数据部分** (仍需持久化):
- ❌ 工作区设置 (`~/.vscode-server/data/Machine/settings.json`)
- ❌ 用户安装的扩展
- ❌ 扩展配置和数据
- ❌ 终端历史、命令历史
- ❌ Git 配置、SSH 密钥

**结论**: 即使镜像已优化, HOME 目录的用户数据仍然需要持久化!

### 原因 4: 多仓库支持

**挂载到 HOME**:
```bash
/home/vscode/
├── project-a/       ← 用户可以克隆多个仓库
├── project-b/
└── project-c/
```

**挂载到 /workspaces**:
```bash
/workspaces/
└── my-repo/         ← 只能有一个仓库? 或需要特殊处理?
```

---

## 实施方案: 最小改动对齐

### 阶段 1: 调整 K8s 挂载点 (核心变更)

#### 变更 1.1: Deployment YAML

**当前配置** (`examples/gitspace-vscode.yaml`):
```yaml
containers:
- name: vscode-ide
  volumeMounts:
  - name: workspace
    mountPath: /workspaces      # ← 当前挂载点
  env:
  - name: WORKSPACE_DIR
    value: "/workspaces"
  - name: REPO_NAME
    value: "my-repo"
  workingDir: /workspaces
```

**新配置** (对齐 Docker):
```yaml
containers:
- name: vscode-ide
  volumeMounts:
  - name: home
    mountPath: /home/vscode     # ← 改为 HOME 目录
  env:
  - name: HOME
    value: "/home/vscode"
  - name: USER
    value: "vscode"
  - name: REPO_NAME
    value: "my-repo"
  workingDir: /home/vscode      # ← 工作目录 = HOME
  securityContext:
    runAsUser: 1000             # ← 以 vscode 用户运行
    runAsGroup: 1000

volumes:
- name: home                     # ← 卷名称改为 home
  persistentVolumeClaim:
    claimName: gitspace-demo-pvc
```

#### 变更 1.2: InitContainer (用户检测和创建)

```yaml
initContainers:
# 阶段 1: 检测用户配置
- name: detect-user
  image: gitness/gitspace:vscode-latest
  command: ["/bin/bash", "-c"]
  args:
    - |
      set -euo pipefail

      # 检测用户配置
      source /usr/local/gitspace/scripts/detect-devcontainer-user.sh

      # 注意: 此时还没有克隆代码, 无法读取 devcontainer.json
      # 暂时使用默认值, 后续在 gitspace-init 中重新检测
      echo "export CONTAINER_USER='vscode'" > /shared/user-config.env
      echo "export REMOTE_USER='vscode'" >> /shared/user-config.env
      echo "export USER_UID='1000'" >> /shared/user-config.env
      echo "export USER_GID='1000'" >> /shared/user-config.env
      echo "export HOME_DIR='/home/vscode'" >> /shared/user-config.env

      cat /shared/user-config.env
  volumeMounts:
  - name: shared
    mountPath: /shared

# 阶段 2: 创建用户和初始化环境
- name: gitspace-init
  image: gitness/gitspace:vscode-latest
  command: ["/bin/bash", "-c"]
  args:
    - |
      set -euo pipefail

      # 加载用户配置
      source /shared/user-config.env

      # 创建或更新用户
      source /usr/local/gitspace/scripts/create-user-dynamic.sh
      create_or_update_user "$CONTAINER_USER" "$USER_UID" "$USER_GID" "$HOME_DIR"

      # 确保 HOME 目录权限正确
      chown -R "$USER_UID:$USER_GID" "$HOME_DIR"

      echo "User initialization completed"
  volumeMounts:
  - name: shared
    mountPath: /shared
  - name: home
    mountPath: /home/vscode
  securityContext:
    runAsUser: 0  # InitContainer 需要 root 创建用户
```

### 阶段 2: 调整 Init 脚本

#### 变更 2.1: `vscode/init-vscode.sh`

**当前**:
```bash
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspaces}"
REPO_NAME="${REPO_NAME:-}"
REPO_DIR="$WORKSPACE_DIR/$REPO_NAME"
```

**调整为**:
```bash
# 使用 HOME 目录而不是 WORKSPACE_DIR
HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-}"
REPO_DIR="$HOME_DIR/$REPO_NAME"

# 向后兼容: 如果设置了 WORKSPACE_DIR, 优先使用 (但打印警告)
if [ -n "${WORKSPACE_DIR:-}" ] && [ "$WORKSPACE_DIR" != "$HOME_DIR" ]; then
    log_info "⚠️  检测到 WORKSPACE_DIR=$WORKSPACE_DIR, 但推荐使用 HOME=$HOME_DIR"
    log_info "为了与 Docker Gitspace 一致, 将使用 HOME 目录"
fi
```

#### 变更 2.2: `base/scripts/clone-repository.sh`

**当前**:
```bash
workspace_dir="${WORKSPACE_DIR:-/workspaces}"
```

**调整为**:
```bash
# 优先使用 HOME 目录 (对齐 Docker)
workspace_dir="${HOME:-/home/vscode}"

# 向后兼容
if [ -n "${WORKSPACE_DIR:-}" ]; then
    workspace_dir="$WORKSPACE_DIR"
fi

log_info "Cloning repository to: $workspace_dir/$repo_name"
```

### 阶段 3: 向后兼容处理

#### 3.1 创建符号链接

在 InitContainer 中添加:

```bash
# 向后兼容: 创建 /workspaces 符号链接指向 HOME
if [ ! -e /workspaces ]; then
    ln -s /home/vscode /workspaces
    log_info "Created symlink: /workspaces -> /home/vscode (for backward compatibility)"
fi
```

#### 3.2 数据迁移脚本

对于现有部署, 提供迁移脚本:

```bash
#!/bin/bash
# migrate-to-home.sh
# 将现有 PVC 数据从 /workspaces 结构迁移到 /home/{user} 结构

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

# 检测是否需要迁移
if [ -d /workspaces ] && [ ! -L /workspaces ]; then
    log_info "检测到旧的 /workspaces 挂载, 开始迁移..."

    # 确定目标用户
    TARGET_USER="${REMOTE_USER:-vscode}"
    TARGET_HOME="/home/$TARGET_USER"

    # 创建 HOME 目录
    mkdir -p "$TARGET_HOME"

    # 移动所有仓库到 HOME
    log_info "移动代码仓库到 $TARGET_HOME ..."
    for repo in /workspaces/*; do
        if [ -d "$repo" ]; then
            repo_name=$(basename "$repo")
            log_info "  移动: $repo -> $TARGET_HOME/$repo_name"
            mv "$repo" "$TARGET_HOME/"
        fi
    done

    # 删除旧目录, 创建符号链接
    rmdir /workspaces 2>/dev/null || rm -rf /workspaces
    ln -s "$TARGET_HOME" /workspaces

    log_info "迁移完成! /workspaces -> $TARGET_HOME"
else
    log_info "无需迁移或已经迁移"
fi
```

---

## 完整的 Deployment 模板 (对齐 Docker)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitspace-demo-pvc
  namespace: gitspace-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitspace-demo-vscode
  namespace: gitspace-demo
  labels:
    app: gitspace
    ide: vscode
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitspace
      ide: vscode
  template:
    metadata:
      labels:
        app: gitspace
        ide: vscode
    spec:
      # Pod 级别 securityContext
      securityContext:
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch

      # InitContainers
      initContainers:
      # 阶段 1: 用户检测 (简化版, 使用默认值)
      - name: detect-user
        image: gitness/gitspace:vscode-latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -euo pipefail
            echo "export CONTAINER_USER='vscode'" > /shared/user-config.env
            echo "export REMOTE_USER='vscode'" >> /shared/user-config.env
            echo "export USER_UID='1000'" >> /shared/user-config.env
            echo "export USER_GID='1000'" >> /shared/user-config.env
            echo "export HOME_DIR='/home/vscode'" >> /shared/user-config.env
            cat /shared/user-config.env
        volumeMounts:
        - name: shared
          mountPath: /shared

      # 阶段 2: 用户创建和环境初始化
      - name: gitspace-init
        image: gitness/gitspace:vscode-latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -euo pipefail

            source /shared/user-config.env

            # 创建用户
            source /usr/local/gitspace/scripts/create-user-dynamic.sh
            create_or_update_user "$CONTAINER_USER" "$USER_UID" "$USER_GID" "$HOME_DIR"

            # 数据迁移 (如果需要)
            if [ -d /data/workspaces ] && [ ! -L /data/workspaces ]; then
                echo "[MIGRATE] 检测到旧结构, 开始迁移..."
                for repo in /data/workspaces/*; do
                    if [ -d "$repo" ]; then
                        repo_name=$(basename "$repo")
                        echo "[MIGRATE]   移动: $repo -> $HOME_DIR/$repo_name"
                        mv "$repo" "$HOME_DIR/" || true
                    fi
                done
                rmdir /data/workspaces 2>/dev/null || rm -rf /data/workspaces
            fi

            # 创建向后兼容符号链接
            if [ ! -e /data/workspaces ]; then
                ln -s "$HOME_DIR" /data/workspaces
                echo "[INFO] 创建符号链接: /workspaces -> $HOME_DIR"
            fi

            # 初始化脚本
            /usr/local/bin/gitspace-init.sh
        env:
        - name: HOME
          value: "/home/vscode"
        - name: REPO_NAME
          value: "test"
        - name: REPO_URL
          value: "https://github.com/your-org/test.git"
        - name: GIT_USERNAME
          valueFrom:
            secretKeyRef:
              name: git-credentials
              key: username
              optional: true
        - name: GIT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: git-credentials
              key: password
              optional: true
        volumeMounts:
        - name: shared
          mountPath: /shared
        - name: home
          mountPath: /data  # InitContainer 临时挂载点
        securityContext:
          runAsUser: 0  # 需要 root 创建用户

      # 主容器
      containers:
      - name: vscode-ide
        image: gitness/gitspace:vscode-latest
        command: ["/shared/start.sh"]
        ports:
        - containerPort: 8089
          name: vscode
          protocol: TCP
        env:
        - name: HOME
          value: "/home/vscode"
        - name: USER
          value: "vscode"
        - name: REPO_NAME
          value: "test"
        - name: IDE_PORT
          value: "8089"
        volumeMounts:
        - name: home
          mountPath: /home/vscode  # ← 挂载到 HOME
        - name: shared
          mountPath: /shared
        workingDir: /home/vscode    # ← 工作目录 = HOME
        securityContext:
          runAsUser: 1000           # ← 以 vscode 用户运行
          runAsGroup: 1000
          allowPrivilegeEscalation: false
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"

      volumes:
      - name: home
        persistentVolumeClaim:
          claimName: gitspace-demo-pvc
      - name: shared
        emptyDir: {}

---
apiVersion: v1
kind: Service
metadata:
  name: gitspace-demo-vscode
  namespace: gitspace-demo
spec:
  selector:
    app: gitspace
    ide: vscode
  ports:
  - port: 8089
    targetPort: 8089
    protocol: TCP
    name: vscode
```

---

## 一致性验证检查清单

### 检查 1: 挂载点一致性

```bash
# Docker
docker inspect gitspace-xxx | jq '.[0].Mounts'
# 预期: 挂载到 /home/vscode

# K8s
kubectl describe pod gitspace-demo-vscode-xxx -n gitspace-demo | grep -A 5 "Mounts:"
# 预期: 挂载到 /home/vscode
```

### 检查 2: 工作目录一致性

```bash
# Docker
docker exec gitspace-xxx pwd
# 预期: /home/vscode

# K8s
kubectl exec -it gitspace-demo-vscode-xxx -n gitspace-demo -- pwd
# 预期: /home/vscode
```

### 检查 3: 用户一致性

```bash
# Docker
docker exec gitspace-xxx id
# 预期: uid=1000(vscode) gid=1000(vscode) groups=1000(vscode)

# K8s
kubectl exec -it gitspace-demo-vscode-xxx -n gitspace-demo -- id
# 预期: uid=1000(vscode) gid=1000(vscode) groups=1000(vscode)
```

### 检查 4: 代码路径一致性

```bash
# Docker
docker exec gitspace-xxx ls -la /home/vscode/
# 预期: 看到 my-repo/

# K8s
kubectl exec -it gitspace-demo-vscode-xxx -n gitspace-demo -- ls -la /home/vscode/
# 预期: 看到 test/
```

### 检查 5: 持久化验证

```bash
# 创建测试文件
kubectl exec -it gitspace-demo-vscode-xxx -n gitspace-demo -- bash -c "echo 'test' > /home/vscode/.test-persistence"

# 重启 Pod
kubectl delete pod gitspace-demo-vscode-xxx -n gitspace-demo

# 等待新 Pod 启动
kubectl wait --for=condition=Ready pod -l app=gitspace -n gitspace-demo --timeout=300s

# 验证文件是否存在
kubectl exec -it $(kubectl get pod -l app=gitspace -n gitspace-demo -o name) -n gitspace-demo -- cat /home/vscode/.test-persistence
# 预期: 输出 "test"
```

---

## 实施步骤

### Week 1: 原型验证

- [x] ✅ 确认 Docker Gitspace 挂载点 (`/home/{username}`)
- [x] ✅ 创建用户检测和创建脚本
- [ ] 🔄 创建新的 Deployment YAML (挂载到 HOME)
- [ ] 🔄 在测试环境验证功能
- [ ] 🔄 验证一致性 (5 项检查)

### Week 2: 脚本调整

- [ ] 调整 `vscode/init-vscode.sh` 使用 HOME 目录
- [ ] 调整 `cursor/init-cursor.sh` 使用 HOME 目录
- [ ] 调整 `jetbrains/init-jetbrains.sh` 使用 HOME 目录
- [ ] 调整 `base/scripts/clone-repository.sh` 使用 HOME 目录
- [ ] 集成测试

### Week 3: 迁移工具

- [ ] 创建数据迁移脚本
- [ ] 测试迁移流程
- [ ] 创建向后兼容符号链接
- [ ] 更新所有示例 YAML

### Week 4: 文档和发布

- [ ] 更新 README
- [ ] 创建迁移指南
- [ ] 灰度发布
- [ ] 全量发布

---

## 预期收益 (在镜像已优化的前提下)

### 1. 用户配置持久化

**当前**: 每次重启丢失
- `.bashrc`, `.profile` 等 Shell 配置
- `.gitconfig` Git 配置
- `.ssh/` SSH 密钥
- IDE 工作区设置

**改进后**: 完全持久化 ✅

### 2. 多仓库支持

**当前**: 受限或需要特殊处理

**改进后**: 用户可以在 `~/` 下管理多个仓库 ✅

### 3. 与 Docker 行为一致

**当前**: 路径和挂载点不同

**改进后**: 100% 一致 ✅

### 4. 符合用户习惯

**当前**: `/workspaces` 不是标准 Linux 路径

**改进后**: 使用标准 HOME 目录 ✅

---

## 总结

**核心变更**:
- PVC 挂载从 `/workspaces` 改为 `/home/vscode`
- 工作目录从 `/workspaces` 改为 `/home/vscode`
- 代码路径从 `/workspaces/{repo}` 改为 `/home/vscode/{repo}`

**收益**:
- ✅ 用户配置完全持久化
- ✅ 与 Docker Gitspace 100% 一致
- ✅ 多仓库自然支持
- ✅ 符合 Linux 标准和用户习惯

**成本**:
- 存储使用相同 (只是挂载位置不同)
- 需要调整脚本和 YAML
- 需要提供迁移工具

**时间**: 4 周完成

---

**文档版本**: v2.0
**日期**: 2025-11-05
**状态**: 待实施
