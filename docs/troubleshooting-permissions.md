# 权限问题排查指南

## 问题: "Permission denied" when cloning repository

### 症状
```
fatal: could not create work tree dir '/workspace/test': Permission denied
[ERROR] 2025-11-05 10:06:33 - Failed to clone repository after 3 attempts
```

### 根本原因
在 Kubernetes 环境中,PVC 挂载的目录权限可能与容器运行的用户不匹配:

1. **securityContext 设置**: Pod 以 `runAsUser: 1000` (vscode 用户) 运行
2. **PVC 实际权限**: 某些存储类(如 hostPath, local-path-provisioner)默认创建 root(0:0) 所有的目录
3. **结果**: vscode 用户无法在 `/workspace` 下创建子目录

### 解决方案

#### 自动修复 (已实施)
`clone-repository.sh` 现在会自动检测和修复权限:

```bash
# 检查当前用户与目录所有者
current_user=$(id -u)
workspace_owner=$(stat -c '%u' "$workspace_dir")

# 如果不匹配,使用 sudo 修复权限
if [ "$workspace_owner" != "$current_user" ]; then
    sudo chown -R "$current_user:$current_group" "$workspace_dir"
fi
```

#### 手动修复
如果自动修复失败,可以手动添加 initContainer:

```yaml
initContainers:
- name: fix-permissions
  image: busybox
  command: ['sh', '-c', 'chown -R 1000:1000 /workspace']
  volumeMounts:
  - name: workspace
    mountPath: /workspace
  securityContext:
    runAsUser: 0  # 必须以 root 运行才能 chown
```

#### StorageClass 配置
对于生产环境,建议配置支持 fsGroup 的 StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gitspace-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
# 确保支持 fsGroup
allowVolumeExpansion: true
```

### 验证修复
1. 检查 initContainer 日志:
   ```bash
   kubectl logs -n gitspace-demo gitspace-vscode-xxx -c gitspace-init
   ```

2. 查找权限修复日志:
   ```
   [INFO] Fixing workspace permissions (current owner: 0, expected: 1000)
   ```

3. 验证目录权限:
   ```bash
   kubectl exec -n gitspace-demo gitspace-vscode-xxx -- ls -la /workspace
   ```

### 不同存储后端的注意事项

| 存储类型 | fsGroup 支持 | 需要修复 |
|---------|-------------|---------|
| hostPath | ❌ | ✅ 是 |
| local-path-provisioner | ⚠️ 部分 | ✅ 是 |
| NFS | ✅ 是 | ❌ 否 |
| AWS EBS | ✅ 是 | ❌ 否 |
| GCE PD | ✅ 是 | ❌ 否 |
| Azure Disk | ✅ 是 | ❌ 否 |

### 相关配置文件
- `/Users/ysicing/Work/github/ysicing/gitspace-runtime/base/scripts/clone-repository.sh:27-41`
- `/Users/ysicing/Work/github/ysicing/gitspace-runtime/examples/gitspace-vscode.yaml:40-45`

### 参考文档
- [Kubernetes Pod Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volume Permissions](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/#access-control)
