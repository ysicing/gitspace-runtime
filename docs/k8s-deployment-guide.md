# K8s Gitspace 部署指南 (使用预装镜像)

## 概述

本指南说明如何部署使用预装镜像的 K8s Gitspace,实现开箱即用,无需在线下载 IDE。

### 核心优势

| 特性 | 传统方式 | 预装镜像方式 |
|------|---------|------------|
| **启动时间** | 3-5 分钟 | 30-60 秒 ⚡ |
| **网络依赖** | 必须联网下载 IDE | 离线可用 ✅ |
| **稳定性** | 受网络影响 | 稳定可靠 ✅ |
| **资源占用** | 运行时下载消耗带宽 | 镜像一次拉取 ✅ |

---

## 前置要求

### 1. 构建镜像

```bash
cd /Users/ysicing/Work/github/ysicing/gitspace-runtime

# 构建所有镜像
make build-all

# 推送到镜像仓库
make push-all
```

**预期输出**:
```
✅ 基础镜像构建完成: ghcr.io/ysicing/gitspace-runtime:base-latest
✅ VSCode 镜像构建完成: ghcr.io/ysicing/gitspace-runtime:vscode-latest
```

### 2. 验证镜像

```bash
# 测试基础镜像
make test-base

# 测试 VSCode 镜像
make test-vscode
```

**预期输出**:
```
🧪 测试 VSCode 镜像...
✅ code-server 已安装: 4.x.x
✅ VSCode 脚本: 已存在
✅ VSCode 镜像测试通过
```

---

## 快速开始

### 方式 1: 使用简化配置 (推荐用于测试)

```bash
# 部署
kubectl apply -f examples/gitspace-vscode-prebuilt.yaml

# 等待 Pod 就绪
kubectl wait --for=condition=Ready pod -l app=gitspace -n gitspace-demo --timeout=300s

# 端口转发
kubectl port-forward -n gitspace-demo svc/gitspace-vscode 8089:8089

# 访问
open http://localhost:8089
```

**预期启动时间**: 30-60 秒

### 方式 2: 使用完整配置

```bash
# 部署
kubectl apply -f examples/gitspace-vscode.yaml

# 查看初始化日志
kubectl logs -n gitspace-demo -l app=gitspace -c gitspace-init --follow

# 查看主容器日志
kubectl logs -n gitspace-demo -l app=gitspace -c vscode-ide --follow
```

---

## 配置说明

### 关键配置项

#### 1. 镜像配置

```yaml
initContainers:
- name: gitspace-init
  image: ghcr.io/ysicing/gitspace-runtime:vscode-latest  # 预装镜像

containers:
- name: vscode-ide
  image: ghcr.io/ysicing/gitspace-runtime:vscode-latest  # 同一镜像
```

**重要**: InitContainer 和主容器使用相同的预装镜像。

#### 2. 环境变量

```yaml
env:
- name: REPO_URL
  value: "https://github.com/your/repo.git"  # 仓库 URL
- name: REPO_NAME
  value: "repo"                              # 仓库名称
- name: BRANCH
  value: "main"                              # 分支
- name: GIT_USERNAME
  value: "your-username"                     # Git 用户名 (可选)
- name: GIT_PASSWORD
  value: "your-token"                        # Git Token (可选)
```

#### 3. 持久化卷

```yaml
volumes:
- name: home
  persistentVolumeClaim:
    claimName: gitspace-vscode-pvc

volumeMounts:
- name: home
  mountPath: /home/vscode  # 挂载到 HOME 目录 (对齐 Docker)
```

**关键点**: 卷挂载到 `/home/vscode`,与 Docker Gitspace 一致。

---

## 验证部署

### 1. 检查 Pod 状态

```bash
kubectl get pods -n gitspace-demo
```

**预期输出**:
```
NAME                               READY   STATUS    RESTARTS   AGE
gitspace-vscode-xxx-yyy            1/1     Running   0          1m
```

### 2. 检查初始化日志

```bash
kubectl logs -n gitspace-demo -l app=gitspace -c gitspace-init
```

**预期输出**:
```
==========================================
🚀 Gitspace 初始化 (使用预装镜像)
==========================================
✅ code-server: 4.x.x
✅ Docker Gitspace 脚本: 已加载
✅ 初始化完成
```

### 3. 检查 code-server 启动

```bash
kubectl logs -n gitspace-demo -l app=gitspace -c vscode-ide
```

**预期输出**:
```
==========================================
🚀 启动 VSCode Server (已预装!)
==========================================
4.x.x xxx
✅ 工作目录: /home/vscode/repo
✅ 端口: 8089
✅ 启动中...
[info] code-server 4.x.x xxx
[info] HTTP server listening on http://0.0.0.0:8089/
```

### 4. 验证 code-server 未下载

**关键指标**: 日志中不应该出现 "Downloading code-server" 或类似下载提示!

✅ **正确**: 直接看到 "code-server 4.x.x" 和 "HTTP server listening"

❌ **错误**: 如果看到下载日志,说明镜像未正确预装

---

## 性能对比

### 启动时间测试

**测试方法**:
```bash
# 记录开始时间
START_TIME=$(date +%s)

# 部署
kubectl apply -f examples/gitspace-vscode-prebuilt.yaml

# 等待就绪
kubectl wait --for=condition=Ready pod -l app=gitspace -n gitspace-demo --timeout=300s

# 记录结束时间
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "启动耗时: ${ELAPSED} 秒"
```

**预期结果**:
- ✅ **预装镜像**: 30-60 秒
- ❌ **传统方式**: 180-300 秒

### 网络流量对比

**首次部署**:
- 镜像拉取: ~800MB (一次性)
- IDE 下载: 0 MB ✅

**后续启动**:
- 镜像拉取: 0 MB (已缓存)
- IDE 下载: 0 MB ✅

---

## 一致性验证

### 运行验证脚本

如果您同时部署了 Docker Gitspace,可以运行一致性验证:

```bash
# 获取 Docker 容器名
DOCKER_CONTAINER=$(docker ps --filter "name=gitspace" --format "{{.Names}}" | head -1)

# 获取 K8s Pod 名
K8S_POD=$(kubectl get pod -n gitspace-demo -l app=gitspace -o jsonpath='{.items[0].metadata.name}')

# 运行验证
bash verify-docker-k8s-consistency.sh "$DOCKER_CONTAINER" "$K8S_POD" gitspace-demo
```

**预期输出**:
```
========================================
测试总结
========================================
通过: 16
失败: 0
警告: 0

✓ 完美! Docker 和 K8s 完全一致!
```

---

## 常见问题

### 1. 镜像拉取失败

**问题**: `ErrImagePull` 或 `ImagePullBackOff`

**解决方案**:

```bash
# 检查镜像是否存在
docker images | grep gitspace-runtime

# 确认镜像已推送
docker pull ghcr.io/ysicing/gitspace-runtime:vscode-latest

# 如果使用私有仓库,配置 imagePullSecrets
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=your-username \
  --docker-password=your-token \
  -n gitspace-demo

# 更新 deployment 使用 secret
kubectl patch deployment gitspace-vscode -n gitspace-demo -p '
{
  "spec": {
    "template": {
      "spec": {
        "imagePullSecrets": [{"name": "regcred"}]
      }
    }
  }
}'
```

### 2. code-server 仍在下载

**问题**: 日志显示正在下载 code-server

**原因**: 使用了错误的镜像或镜像未正确预装

**解决方案**:

```bash
# 验证镜像内容
docker run --rm ghcr.io/ysicing/gitspace-runtime:vscode-latest code-server --version

# 预期输出: 4.x.x
# 如果报错 "command not found", 说明镜像未预装

# 重新构建镜像
cd /Users/ysicing/Work/github/ysicing/gitspace-runtime
make build-vscode
make push-vscode
```

### 3. 持久化数据丢失

**问题**: 重启后配置和代码丢失

**原因**: PVC 未正确挂载到 HOME 目录

**解决方案**:

```bash
# 检查挂载点
kubectl exec -n gitspace-demo -it <pod-name> -- mount | grep /home/vscode

# 预期输出: 类似 /dev/xxx on /home/vscode type ext4 ...

# 检查符号链接
kubectl exec -n gitspace-demo -it <pod-name> -- ls -la /workspaces

# 预期输出: lrwxrwxrwx ... /workspaces -> /home/vscode
```

### 4. 启动时间仍然很慢

**问题**: 启动超过 2 分钟

**可能原因**:
1. 镜像层未缓存 (首次拉取)
2. PVC 性能差 (使用 NFS 等慢速存储)
3. CPU/内存限制过低

**解决方案**:

```bash
# 检查资源限制
kubectl describe pod -n gitspace-demo -l app=gitspace

# 调整资源配置
kubectl patch deployment gitspace-vscode -n gitspace-demo -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "vscode-ide",
          "resources": {
            "requests": {"memory": "1Gi", "cpu": "500m"},
            "limits": {"memory": "2Gi", "cpu": "1000m"}
          }
        }]
      }
    }
  }
}'
```

---

## 高级配置

### 1. 预装扩展

在 Dockerfile 中添加扩展:

```dockerfile
# vscode/Dockerfile
ARG VSCODE_EXTENSIONS="dbaeumer.vscode-eslint,esbenp.prettier-vscode,golang.go"

RUN for ext in $(echo "${VSCODE_EXTENSIONS}" | tr ',' ' '); do \
        code-server --install-extension "${ext}"; \
    done
```

### 2. 多仓库支持

修改 InitContainer 支持克隆多个仓库:

```yaml
env:
- name: REPO_URLS
  value: "https://github.com/org/repo1.git,https://github.com/org/repo2.git"
```

### 3. 自定义镜像

基于预装镜像构建自定义镜像:

```dockerfile
FROM ghcr.io/ysicing/gitspace-runtime:vscode-latest

# 安装额外工具
RUN apt-get update && apt-get install -y \
    python3-pip \
    && pip3 install pytest black

# 安装额外扩展
RUN code-server --install-extension ms-python.python
```

---

## 下一步

### 生产环境部署

1. **配置 Ingress**:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: gitspace-vscode
     namespace: gitspace-demo
   spec:
     rules:
     - host: vscode.example.com
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: gitspace-vscode
               port:
                 number: 8089
   ```

2. **启用认证**:
   修改 code-server 配置启用密码认证:
   ```yaml
   auth: password
   password: your-secure-password
   ```

3. **配置 TLS**:
   使用 cert-manager 自动签发 TLS 证书

4. **配置 HPA**:
   根据负载自动扩缩容

---

## 参考文档

- [统一架构设计](../docs/unified-runtime-design.md)
- [实施进展报告](../docs/unified-runtime-progress.md)
- [Makefile 使用指南](../Makefile) - 运行 `make help`
- [一致性验证脚本](../verify-docker-k8s-consistency.sh)

---

**更新时间**: 2025-11-05
**版本**: v1.0
