# 工作目录标准化迁移指南

## 概述

本次更新将工作目录从 `/workspace` (单数) 统一到 `/workspaces` (复数),以符合 VS Code Dev Container 标准和 Gitness Docker 实现。

---

## 变更内容

### 1. 目录路径更改

| 组件 | 旧路径 | 新路径 | 状态 |
|------|--------|--------|------|
| 基础镜像 WORKDIR | `/workspace` | `/workspaces` | ✅ 已更改 |
| 克隆脚本默认值 | `/workspace` | `/workspaces` | ✅ 已更改 |
| VSCode init 脚本 | `/workspace` | `/workspaces` | ✅ 已更改 |
| Cursor init 脚本 | `/workspace` | `/workspaces` | ✅ 已更改 |
| JetBrains init 脚本 | `/workspace` | `/workspaces` | ✅ 已更改 |
| 示例 YAML 文件 | `/workspace` | `/workspaces` | ✅ 已更改 |

### 2. 向后兼容性

为确保现有部署不受影响,在基础镜像中添加了软链接:

```dockerfile
RUN ln -s /workspaces /workspace
```

这意味着:
- 旧路径 `/workspace` 仍然可用
- 新部署应使用 `/workspaces`
- 逐步迁移,无需立即升级所有配置

---

## 迁移步骤

### 对于新部署

**推荐**: 直接使用新路径 `/workspaces`

```yaml
env:
- name: WORKSPACE_DIR
  value: "/workspaces"  # 使用新路径

volumeMounts:
- name: workspace
  mountPath: /workspaces  # 使用新路径
```

### 对于现有部署

#### 选项 1: 不做任何更改 (推荐)

由于添加了软链接,现有配置无需修改即可继续工作:

```yaml
env:
- name: WORKSPACE_DIR
  value: "/workspace"  # 旧路径仍然有效

volumeMounts:
- name: workspace
  mountPath: /workspace  # 旧路径仍然有效
```

#### 选项 2: 更新到新路径 (可选)

如果您希望遵循最佳实践:

1. **更新 Deployment 配置**:
   ```bash
   # 编辑您的 deployment
   kubectl edit deployment gitspace-vscode -n your-namespace

   # 将所有 /workspace 改为 /workspaces
   ```

2. **更新环境变量**:
   ```yaml
   # 从
   - name: WORKSPACE_DIR
     value: "/workspace"

   # 改为
   - name: WORKSPACE_DIR
     value: "/workspaces"
   ```

3. **更新卷挂载**:
   ```yaml
   # 从
   volumeMounts:
   - name: workspace
     mountPath: /workspace

   # 改为
   volumeMounts:
   - name: workspace
     mountPath: /workspaces
   ```

4. **重启 Pod**:
   ```bash
   kubectl rollout restart deployment gitspace-vscode -n your-namespace
   ```

---

## 验证迁移

### 检查目录结构

```bash
# 进入 Pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# 验证新路径存在
ls -la /workspaces

# 验证软链接存在
ls -la / | grep workspace

# 应该看到:
# lrwxrwxrwx  1 root   root     10 ... /workspace -> /workspaces
# drwxr-xr-x  3 vscode vscode 4096 ... /workspaces
```

### 检查仓库克隆

```bash
# 验证仓库在新路径下
ls -la /workspaces/<your-repo-name>

# 验证旧路径也可访问(软链接)
ls -la /workspace/<your-repo-name>
```

### 检查 IDE 启动

```bash
# 检查日志确认路径正确
kubectl logs <pod-name> -n <namespace> -c gitspace-init

# 应该看到类似:
# [INFO] Target directory: /workspaces/my-repo
# [INFO] Repository cloned successfully
```

---

## devcontainer.json 配置

### 推荐配置

```json
{
  "name": "My Dev Environment",
  "image": "gitness/gitspace:vscode-latest",

  // 使用标准路径
  "workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/${localWorkspaceFolderBasename},type=bind",

  // 用户配置
  "remoteUser": "vscode",
  "containerUser": "vscode"
}
```

### 兼容旧配置

如果您的 devcontainer.json 使用旧路径,也无需修改:

```json
{
  // 旧配置仍然有效(通过软链接)
  "workspaceFolder": "/workspace/my-repo",
  "workspaceMount": "...,target=/workspace/my-repo,..."
}
```

---

## 常见问题

### Q1: 我需要立即更新吗?

**A**: 不需要。软链接确保了向后兼容性,您可以按自己的节奏迁移。

### Q2: 更新后 PVC 数据会丢失吗?

**A**: 不会。PVC 中的数据路径不变,只是访问路径从 `/workspace` 变为 `/workspaces` (或通过软链接访问)。

### Q3: 为什么要使用 /workspaces (复数)?

**A**:
1. 符合 VS Code Dev Container [官方规范](https://containers.dev/)
2. 与 Gitness Docker 实现保持一致
3. 支持多工作区场景

### Q4: 软链接会影响性能吗?

**A**: 不会。软链接的性能开销可以忽略不计。

### Q5: 我可以删除软链接吗?

**A**: 可以,但请确保:
1. 所有配置已更新到新路径
2. 没有硬编码的旧路径引用
3. 所有用户知晓变更

删除软链接:
```dockerfile
# 在自定义 Dockerfile 中
RUN rm /workspace
```

---

## 回滚步骤

如果遇到问题,可以回滚到旧镜像:

```bash
# 回滚 Deployment
kubectl rollout undo deployment gitspace-vscode -n your-namespace

# 或指定特定版本
kubectl rollout undo deployment gitspace-vscode -n your-namespace --to-revision=<revision-number>
```

---

## 支持和反馈

如有问题或建议,请:

1. 查看 [troubleshooting-permissions.md](./troubleshooting-permissions.md)
2. 查看 [user-permissions-audit.md](./user-permissions-audit.md)
3. 提交 Issue 到项目仓库

---

## 时间线

- **2025-11-05**: 初始版本发布,添加软链接支持
- **2025-12-05**: (计划) 所有示例和文档更新完成
- **2026-01-05**: (计划) 开始弃用软链接的警告
- **2026-06-05**: (计划) 移除软链接,完全切换到 `/workspaces`

---

## 相关文档

- [用户权限审计报告](./user-permissions-audit.md)
- [权限问题排查指南](./troubleshooting-permissions.md)
- [VS Code Dev Container 规范](https://containers.dev/)
- [Kubernetes 卷管理](https://kubernetes.io/docs/concepts/storage/volumes/)
