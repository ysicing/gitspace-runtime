# 持久化架构对比图解

## 1. Docker Gitspace 架构 (官方实现)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Host                               │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              Docker Volume: gitness-{id}                │    │
│  │                  (持久化存储)                           │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ Volume Mount                            │
│                        ↓                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         Container: gitspace-{id}                         │   │
│  │                                                           │   │
│  │  /home/vscode/  ←─────────── 挂载点                     │   │
│  │  ├── .bashrc                      (持久化) ✅           │   │
│  │  ├── .vscode-server/              (持久化) ✅           │   │
│  │  │   ├── bin/                                            │   │
│  │  │   ├── data/                                           │   │
│  │  │   └── extensions/                                     │   │
│  │  ├── .config/                     (持久化) ✅           │   │
│  │  ├── .cache/                      (持久化) ✅           │   │
│  │  ├── my-repo/                     (持久化) ✅           │   │
│  │  │   ├── .git/                                           │   │
│  │  │   ├── src/                                            │   │
│  │  │   └── README.md                                       │   │
│  │  └── another-repo/                (持久化) ✅           │   │
│  │                                                           │   │
│  │  Container User: vscode (UID 1000)                      │   │
│  │  Working Directory: /home/vscode                         │   │
│  │  Repo Path: /home/vscode/my-repo                        │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

关键特性:
✅ HOME 目录完全持久化
✅ VS Code Server 持久化 → 重启快 (30-60秒)
✅ 用户配置持久化 → 无需重新设置
✅ 多仓库支持 → 用户可以在 HOME 下管理多个项目
✅ 符合 Linux 文件层次结构标准 (FHS)
```

---

## 2. K8s Runtime 架构 (当前实现)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐    │
│  │        PVC: gitspace-demo-pvc                           │    │
│  │            (持久化存储)                                 │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ Volume Mount                            │
│                        ↓                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         Pod: gitspace-demo-vscode-xxx                    │   │
│  │                                                           │   │
│  │  /workspaces/  ←─────────── 挂载点                      │   │
│  │  └── my-repo/                     (持久化) ✅           │   │
│  │      ├── .git/                                           │   │
│  │      ├── src/                                            │   │
│  │      └── README.md                                       │   │
│  │                                                           │   │
│  │  /home/vscode/  ←─────────── 容器文件系统 (非持久化)   │   │
│  │  ├── .bashrc                      (丢失) ❌             │   │
│  │  ├── .vscode-server/              (丢失) ❌             │   │
│  │  │   ├── bin/         ← 每次重启重新下载 ~200MB        │   │
│  │  │   ├── data/                                           │   │
│  │  │   └── extensions/  ← 每次重启重新安装                │   │
│  │  ├── .config/                     (丢失) ❌             │   │
│  │  └── .cache/                      (丢失) ❌             │   │
│  │                                                           │   │
│  │  Container User: vscode (UID 1000)                      │   │
│  │  Working Directory: /workspaces                          │   │
│  │  Repo Path: /workspaces/my-repo                         │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

问题:
❌ HOME 目录不持久化
❌ VS Code Server 每次重启重新下载 → 重启慢 (3-5分钟)
❌ 用户配置丢失 → 每次重启需要重新设置
⚠️ 多仓库支持受限
⚠️ 与 Docker Gitspace 不一致
```

---

## 3. 重启流程对比

### Docker Gitspace: 快速重启 ⚡

```
用户操作: 停止 Gitspace
    ↓
Docker 停止容器
    ↓
Volume 数据保留在磁盘
    ↓
用户操作: 启动 Gitspace
    ↓
Docker 创建新容器
    ↓
挂载 Volume 到 /home/vscode  ← 所有数据都在!
    ↓
VS Code Server 已存在 ✅      ← 跳过下载!
    ↓
扩展已安装 ✅                  ← 立即可用!
    ↓
用户配置已存在 ✅              ← 无需设置!
    ↓
启动 IDE
    ↓
⏱️ 总耗时: 30-60 秒

用户体验: ⭐⭐⭐⭐⭐ (优秀)
```

### K8s Runtime: 慢速重启 🐢

```
用户操作: 停止 Gitspace
    ↓
Kubernetes 删除 Pod
    ↓
PVC 数据保留 (/workspaces)
HOME 目录数据丢失 (/home/vscode) ❌
    ↓
用户操作: 启动 Gitspace
    ↓
Kubernetes 创建新 Pod
    ↓
挂载 PVC 到 /workspaces         ← 只有代码保留
HOME 目录是空的 ❌
    ↓
检测 VS Code Server 不存在
    ↓
⏳ 下载 VS Code Server (~200MB, 1-2分钟)
    ↓
⏳ 安装 VS Code Server
    ↓
⏳ 重新安装扩展 (可能需要)
    ↓
⏳ 用户配置丢失, 需要重新设置
    ↓
启动 IDE
    ↓
⏱️ 总耗时: 3-5 分钟

用户体验: ⭐⭐ (较差)
```

---

## 4. 方案 A: 完全对齐 Docker (推荐)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐    │
│  │        PVC: gitspace-demo-pvc                           │    │
│  │            (持久化存储)                                 │    │
│  └─────────────────────┬──────────────────────────────────┘    │
│                        │                                         │
│                        │ Volume Mount (调整!)                   │
│                        ↓                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         Pod: gitspace-demo-vscode-xxx                    │   │
│  │                                                           │   │
│  │  /home/vscode/  ←─────────── 挂载点 (新!)              │   │
│  │  ├── .bashrc                      (持久化) ✅           │   │
│  │  ├── .vscode-server/              (持久化) ✅           │   │
│  │  │   ├── bin/                                            │   │
│  │  │   ├── data/                                           │   │
│  │  │   └── extensions/                                     │   │
│  │  ├── .config/                     (持久化) ✅           │   │
│  │  ├── .cache/                      (持久化) ✅           │   │
│  │  ├── my-repo/                     (持久化) ✅           │   │
│  │  │   ├── .git/                                           │   │
│  │  │   ├── src/                                            │   │
│  │  │   └── README.md                                       │   │
│  │  └── another-repo/                (持久化) ✅           │   │
│  │                                                           │   │
│  │  Container User: vscode (UID 1000)                      │   │
│  │  Working Directory: /home/vscode  (调整!)               │   │
│  │  Repo Path: /home/vscode/my-repo  (调整!)              │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

改进:
✅ 与 Docker Gitspace 100% 一致
✅ HOME 目录完全持久化
✅ VS Code Server 持久化 → 重启快 (30-60秒)
✅ 用户配置持久化 → 无需重新设置
✅ 多仓库自然支持
✅ 符合 Linux FHS 标准

Deployment 配置调整:
volumes:
- name: home
  persistentVolumeClaim:
    claimName: gitspace-demo-pvc

volumeMounts:
- name: home
  mountPath: /home/vscode  # ← 从 /workspaces 改为 /home/vscode

env:
- name: HOME
  value: "/home/vscode"
- name: WORKSPACE_DIR
  value: "/home/vscode"    # ← 或删除, 使用 $HOME

workingDir: /home/vscode   # ← 从 /workspaces 改为 /home/vscode
```

---

## 5. 方案 B: 双卷方案 (折衷)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
│                                                                   │
│  ┌────────────────────────┐  ┌────────────────────────────┐    │
│  │ PVC 1: workspace-pvc    │  │ PVC 2: home-pvc            │    │
│  │   (代码仓库, 10GB)      │  │   (用户数据, 5GB)          │    │
│  └───────────┬─────────────┘  └───────────┬────────────────┘    │
│              │                             │                      │
│              │                             │                      │
│              ↓                             ↓                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         Pod: gitspace-demo-vscode-xxx                    │   │
│  │                                                           │   │
│  │  /workspaces/  ←─ PVC 1                                 │   │
│  │  └── my-repo/                     (持久化) ✅           │   │
│  │      ├── .git/                                           │   │
│  │      ├── src/                                            │   │
│  │      └── README.md                                       │   │
│  │                                                           │   │
│  │  /home/vscode/  ←─ PVC 2                                │   │
│  │  ├── .bashrc                      (持久化) ✅           │   │
│  │  ├── .vscode-server/              (持久化) ✅           │   │
│  │  ├── .config/                     (持久化) ✅           │   │
│  │  └── .cache/                      (持久化) ✅           │   │
│  │                                                           │   │
│  │  Working Directory: /workspaces/my-repo                 │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

优势:
✅ HOME 目录持久化
✅ VS Code Server 持久化
✅ 代码和配置分离管理
✅ 向后兼容 (代码仍在 /workspaces)

劣势:
❌ 与 Docker 不一致 (两个卷 vs 一个卷)
⚠️ 需要管理两个 PVC
⚠️ 存储成本增加
⚠️ 多仓库支持仍不自然
```

---

## 6. 行业标准参考

### GitHub Codespaces

```
/workspaces/{repo}/      ← 代码仓库 (挂载)
/home/codespace/         ← 用户数据 (持久化卷)
├── .vscode-server/      ← IDE 数据
├── .bashrc
└── .gitconfig
```

### VS Code Dev Containers

```
/workspaces/{repo}/          ← 代码仓库 (bind mount)
/home/vscode/.vscode-server/ ← 自动创建 named volume
/home/vscode/.vscode-server/extensions/ ← 自动创建 named volume
```

### JetBrains Projector

```
/home/user/              ← 用户目录 (持久化)
├── .cache/JetBrains/    ← IDE 缓存
├── .config/JetBrains/   ← IDE 配置
└── projects/{repo}/     ← 项目在 HOME 下
```

**共同点**: 都持久化用户 HOME 目录! 🎯

---

## 7. 性能影响对比

### 启动时间

```
┌──────────────────────────────────────────────────────────────┐
│                     启动时间对比 (秒)                         │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  首次启动:                                                    │
│  ████████████████████████  K8s (当前): 180-300s             │
│  ████████████████████████  K8s (方案A): 180-300s  (相同)    │
│  ████████████████████████  Docker: 180-300s      (相同)    │
│                                                               │
│  重启 (VS Code Server 存在):                                  │
│  ████████████████████████  K8s (当前): 180-300s  (重新下载) │
│  ████                       K8s (方案A): 30-60s   (快5倍!)  │
│  ████                       Docker: 30-60s        (快5倍!)  │
│                                                               │
└──────────────────────────────────────────────────────────────┘

⚡ 方案 A 重启速度提升 4-5 倍!
```

### 存储使用

```
┌──────────────────────────────────────────────────────────────┐
│                    存储使用对比 (GB)                          │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  代码仓库: ~1-10GB                                            │
│  ██████████████████  K8s (当前)                              │
│  ██████████████████  K8s (方案A)     (相同)                  │
│  ██████████████████  Docker          (相同)                  │
│                                                               │
│  VS Code Server: ~0.2GB                                       │
│                      K8s (当前)      (每次下载, 不占PVC)     │
│  ██                  K8s (方案A)     (持久化)                │
│  ██                  Docker          (持久化)                │
│                                                               │
│  用户配置: ~0.01GB                                            │
│                      K8s (当前)      (丢失)                  │
│  █                   K8s (方案A)     (持久化)                │
│  █                   Docker          (持久化)                │
│                                                               │
└──────────────────────────────────────────────────────────────┘

📊 存储增加: ~210MB (~10% 对于典型 2GB 仓库)
💰 收益: 节省带宽, 重启快 4-5 倍
```

---

## 8. 迁移路径

### Step 1: 创建迁移脚本

```bash
#!/bin/bash
# migrate-workspaces-to-home.sh

set -euo pipefail

OLD_MOUNT="/workspaces"
NEW_MOUNT="/home/vscode"

echo "开始迁移: $OLD_MOUNT → $NEW_MOUNT"

if [ -d "$OLD_MOUNT" ]; then
    # 检查是否已迁移
    if [ -L "$OLD_MOUNT" ]; then
        echo "已完成迁移, /workspaces 是符号链接"
        exit 0
    fi

    # 复制数据
    echo "复制数据..."
    rsync -av --progress "$OLD_MOUNT/" "$NEW_MOUNT/"

    # 创建备份
    echo "创建备份..."
    mv "$OLD_MOUNT" /workspaces.backup

    # 创建符号链接 (向后兼容)
    ln -s "$NEW_MOUNT" "$OLD_MOUNT"

    echo "迁移完成!"
    echo "  数据位置: $NEW_MOUNT"
    echo "  符号链接: $OLD_MOUNT → $NEW_MOUNT"
    echo "  备份位置: /workspaces.backup"
else
    echo "未发现旧挂载点, 跳过迁移"
fi
```

### Step 2: 更新 Deployment

```yaml
# 旧配置
volumeMounts:
- name: workspace
  mountPath: /workspaces

# 新配置
volumeMounts:
- name: workspace
  mountPath: /home/vscode  # ← 改为 HOME

# 添加 InitContainer 执行迁移
initContainers:
- name: migrate-data
  image: gitness/gitspace:vscode-latest
  command: ["/bin/bash", "/usr/local/gitspace/scripts/migrate-workspaces-to-home.sh"]
  volumeMounts:
  - name: workspace
    mountPath: /data  # 临时挂载点
```

### Step 3: 渐进式部署

```
Week 1: 新 Gitspace 使用新架构
  ↓
Week 2: 现有 Gitspace 自动迁移
  ↓
Week 3: 验证和监控
  ↓
Week 4: 全量迁移完成
```

---

## 9. 决策矩阵

| 方案 | 改动量 | 用户体验 | 一致性 | 成本 | 推荐度 |
|------|-------|---------|--------|------|--------|
| **方案 A: HOME** | 🔴 大 | ⭐⭐⭐⭐⭐ | ✅ 100% | 💰 相同 | ⭐⭐⭐⭐⭐ **推荐** |
| **方案 B: 双卷** | 🟡 中 | ⭐⭐⭐⭐ | ⚠️ 部分 | 💰💰 增加 | ⭐⭐⭐ 可考虑 |
| **方案 C: subPath** | 🟢 小 | ⭐⭐ | ❌ 差 | 💰 相同 | ⭐ 不推荐 |
| **保持现状** | 🟢 无 | ⭐ | ❌ 差 | 💰 相同 | ❌ 不推荐 |

---

## 10. 总结

### 核心问题

🚨 **Docker Gitspace 持久化到 `/home/{username}`, K8s Runtime 持久化到 `/workspaces`**

这导致:
- ❌ 用户体验差 (重启慢 4-5 倍)
- ❌ 与 Docker 不一致
- ❌ 与行业标准不符

### 推荐方案

⭐ **方案 A: 完全对齐 Docker, 挂载 PVC 到用户 HOME 目录**

理由:
1. ✅ 与 Docker Gitspace 100% 一致
2. ⚡ 重启速度提升 4-5 倍
3. 🎯 符合行业标准 (GitHub Codespaces, VS Code)
4. 🚀 未来可扩展性强
5. 💰 长期收益最大

### 下一步

1. **立即决策**: 选择方案 A
2. **Week 1**: 原型验证
3. **Week 2**: 核心实现
4. **Week 3**: 迁移工具
5. **Week 4**: 生产部署

---

**报告时间**: 2025-11-05
**状态**: 🔴 需要立即决策
**建议**: 采用方案 A, 完全对齐 Docker Gitspace
