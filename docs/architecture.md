# Gitspace Runtime 架构设计与实现

**版本**: v1.0
**日期**: 2025-11-06

---

## 概述

Gitspace Runtime 提供 Kubernetes 运行时镜像,采用预装 IDE 的策略实现开箱即用,将启动时间从 3-5 分钟降至 30-60 秒。

### 核心目标

1. **开箱即用** - code-server 预装在镜像中
2. **快速启动** - 5-10倍性能提升
3. **完全离线** - 无需运行时下载
4. **100% 一致** - Docker 和 K8s 行为对齐

---

## 架构设计

### 镜像分层架构

```
ghcr.io/ysicing/gitspace-runtime:base-latest (250MB)
  ├── Ubuntu 24.04 基础镜像
  ├── 通用工具: git, curl, wget, jq
  ├── vscode 用户 (UID: 1000, GID: 1000)
  └── 通用脚本: Git 凭证管理、仓库克隆
      └── /usr/local/gitspace/scripts/common/

ghcr.io/ysicing/gitspace-runtime:vscode-latest (500MB)
  ├── 继承自 base
  ├── VSCode 依赖: build-essential, python3, nodejs, npm
  ├── code-server 4.x 预装 ✅
  ├── VSCode 扩展预装 (可配置)
  └── 用途: Web 浏览器访问 (端口 8089)

ghcr.io/ysicing/gitspace-runtime:vscode-desktop-latest (550MB)
  ├── 继承自 base
  ├── VSCode 依赖: build-essential, python3, nodejs, npm
  ├── ✅ OpenSSH Server 预装 (端口 8088)
  ├── SSH 配置: 密码认证/公钥认证
  └── 用途: VSCode Desktop Remote-SSH 连接

ghcr.io/ysicing/gitspace-runtime:jetbrains-latest (800MB)
  ├── 继承自 base
  ├── JetBrains 依赖: Java 17, X11 库等
  └── 支持 IntelliJ IDEA, PyCharm, GoLand 等

ghcr.io/ysicing/gitspace-runtime:cursor-latest (550MB)
  ├── 继承自 vscode
  └── Cursor/Windsurf 特定配置
```

### 持久化架构

**关键决策**: 挂载到 `/home/vscode` (与 Docker Gitspace 对齐)

```
PersistentVolume
  └── mountPath: /home/vscode
      ├── .config/           # 配置持久化
      ├── .local/            # 用户数据
      ├── .vscode-server/    # VSCode 服务器数据
      └── <repo-name>/       # 代码仓库
```

**优势**:
- ✅ 与 Docker Gitspace 完全一致
- ✅ 用户配置自动持久化
- ✅ 扩展和主题保留
- ✅ 符合 Linux 标准

---

## 脚本系统

### 脚本复用

从 Docker Gitspace 提取 19 个脚本,确保行为一致:

**通用脚本** (8个):
- `clone-code.sh` - 克隆代码到 `$HOME/<repo>`
- `setup-git-credentials.sh` - Git 凭证配置
- `manage-user.sh` - 用户和 HOME 目录管理
- `install-git.sh` - Git 安装
- `set-env.sh` - 环境变量设置
- `setup-ssh-server.sh` - SSH 服务器配置
- `run-ssh-server.sh` - SSH 服务器启动
- `supported-os-distribution.sh` - 操作系统检测

**IDE 专用脚本**:
- VSCode: 5个 (`run_vscode_web.sh`, `install_vscode_web.sh` 等)
- Cursor: 2个
- JetBrains: 4个

### 脚本位置

```
base/scripts/
├── docker-gitspace/          # 从 Docker Gitspace 提取
│   ├── clone-code.sh
│   ├── manage-user.sh
│   └── ...
└── *.sh                      # 统一脚本 (向后兼容)

镜像内路径:
/usr/local/gitspace/scripts/
├── common/                   # 通用脚本
├── vscode/                   # VSCode 脚本
├── cursor/                   # Cursor 脚本
└── jetbrains/                # JetBrains 脚本
```

---

## Kubernetes 部署架构

### Pod 结构

```yaml
apiVersion: v1
kind: Pod
spec:
  initContainers:
  - name: gitspace-init
    image: ghcr.io/ysicing/gitspace-runtime:vscode-latest
    # 初始化: 克隆代码、设置凭证
    volumeMounts:
    - name: home
      mountPath: /home/vscode

  containers:
  - name: vscode-ide
    image: ghcr.io/ysicing/gitspace-runtime:vscode-latest
    # code-server 已预装,直接启动 ✅
    command: ["code-server", "--disable-workspace-trust", "."]
    ports:
    - containerPort: 8089
    volumeMounts:
    - name: home
      mountPath: /home/vscode

  volumes:
  - name: home
    persistentVolumeClaim:
      claimName: gitspace-pvc
```

### 启动流程

```
Pod 创建
  ↓ (10s)
InitContainer 执行
  ├─ 克隆代码到 /home/vscode/<repo>
  ├─ 设置 Git 凭证
  └─ 用户初始化
  ↓ (20s)
主容器启动
  ├─ code-server 已预装 ✅
  ├─ 读取持久化配置
  └─ 直接启动 IDE
  ↓ (5s)
✅ 就绪 (总计 30-60秒)
```

**对比传统方式** (3-5分钟):
```
传统流程:
  Pod 创建 → 下载 code-server (60s) → 安装 (60s) → 配置 (30s) → 启动
```

---

## 构建系统

### Taskfile 架构

使用 Taskfile (Go Task) 作为构建工具:

```yaml
# 核心任务
task build-all          # 构建所有镜像
task push-all           # 推送镜像
task buildx-all         # 多平台构建 (amd64+arm64)
task test-all           # 测试镜像
task release VERSION=x  # 发布版本

# 开发任务
task shell-vscode       # 进入镜像 shell
task inspect-vscode     # 检查镜像信息
task clean              # 清理镜像
```

### 构建流程

```
1. 构建 base 镜像
   ├─ Ubuntu 24.04
   ├─ 安装通用工具
   ├─ 复制脚本到 /usr/local/gitspace/scripts/
   └─ 创建 vscode 用户

2. 构建 vscode 镜像 (依赖 base)
   ├─ 继承 base 镜像
   ├─ 安装 Node.js, npm
   ├─ 预装 code-server ✅
   └─ 预装 VSCode 扩展 (可配置)

3. 构建 cursor 镜像 (依赖 vscode)
   └─ 继承 vscode,添加 Cursor 配置

4. 构建 jetbrains 镜像 (依赖 base)
   ├─ 继承 base 镜像
   ├─ 安装 Java 17
   └─ 配置 JetBrains IDE 支持
```

---

## Gitness 集成

### 配置

在 Gitness 中配置预装镜像 (唯一方式):

```go
// types/config.go
type GitspaceContainerConfig struct {
    PrebuiltImages GitspacePrebuiltImagesConfig
}

type GitspacePrebuiltImagesConfig struct {
    Registry   string `envconfig:"GITSPACE_PREBUILT_IMAGES_REGISTRY" default:"ghcr.io/ysicing/gitspace-runtime"`
    VSCode     string `envconfig:"GITSPACE_PREBUILT_IMAGE_VSCODE" default:"vscode-latest"`
    Cursor     string `envconfig:"GITSPACE_PREBUILT_IMAGE_CURSOR" default:"cursor-latest"`
    JetBrains  string `envconfig:"GITSPACE_PREBUILT_IMAGE_JETBRAINS" default:"jetbrains-latest"`
}
```

### 镜像选择逻辑

```go
// kubernetes_orchestrator.go
func (o *KubernetesOrchestrator) getDefaultBaseImage(ide enum.IDEType) string {
    switch ide {
    case enum.IDETypeVSCodeWeb:
        return o.config.Gitspace.Container.PrebuiltImages.VSCode
    case enum.IDETypeVSCode:  // Desktop 版本
        return o.config.Gitspace.Container.PrebuiltImages.VSCodeDesktop
    case enum.IDETypeCursor:
        return o.config.Gitspace.Container.PrebuiltImages.Cursor
    case enum.IDETypeIntelliJ, enum.IDETypePyCharm, enum.IDETypeGoland:
        return o.config.Gitspace.Container.PrebuiltImages.JetBrains
    default:
        return o.config.Gitspace.Container.PrebuiltImages.VSCode
    }
}
```

**IDE 类型说明**:
- `vs_code_web` - Web 版本，通过浏览器访问 (端口 8089)
- `vs_code` - Desktop 版本，通过 Remote-SSH 连接 (端口 8088)
- 两者使用不同的镜像和连接方式

### 仓库克隆

当前实现支持单仓库场景:

```go
// InitContainer 环境变量
initEnvVars := []corev1.EnvVar{
    {Name: "REPO_URL", Value: resolvedRepoDetails.CloneURL.Value()},
    {Name: "BRANCH", Value: resolvedRepoDetails.Branch},
    {Name: "REPO_NAME", Value: resolvedRepoDetails.RepoName},
    // ...
}
```

克隆到 `/workspace/{REPO_NAME}` 目录。

### 启动步骤 (简化)

K8s Gitspace 使用预装镜像,启动步骤大幅简化:

```go
// kubernetes_steps.go
func (o *KubernetesOrchestrator) buildSetupSteps(...) []KubernetesStep {
    return []KubernetesStep{
        {Name: "Validate OS", Execute: ValidateSupportedOS},
        {Name: "Manage User", Execute: manageUser},
        {Name: "Setup Environment", Execute: setEnvironment},
        {Name: "Clone Code", Execute: CloneCode},
        {Name: "Setup Git Credentials", Execute: SetupGitCredentials},
        {Name: "IDE Run", Execute: IDE.Run},  // IDE 已预装,直接运行
    }
}
```

**关键点**:
- ❌ 无需 `installTools()` - 工具已预装
- ❌ 无需 `IDE.Setup()` - IDE 已预装
- ✅ 直接 `IDE.Run()` - 立即启动

---

## 性能指标

### 启动时间

K8s Gitspace 使用预装镜像后的启动时间:

| 场景 | 启动时间 | 说明 |
|------|---------|------|
| **首次启动** | 30-60 秒 | 包含镜像拉取 |
| **后续启动** | 15-30 秒 | 镜像已缓存 |

### 启动流程分解

```
Pod 创建 (2s)
  ↓
镜像拉取 (10-30s, 首次)
  ↓
InitContainer 执行 (10-20s)
  ├─ 克隆代码
  └─ 设置凭证
  ↓
主容器启动 (5-10s)
  ├─ code-server 已预装 ✅
  └─ 直接启动 IDE
  ↓
✅ 就绪 (30-60秒 首次 / 15-30秒 后续)
```

### 网络流量

K8s Gitspace 使用预装镜像的网络流量:

| 阶段 | 流量 | 说明 |
|------|-----|------|
| **首次拉取** | 800MB | VSCode 镜像大小 |
| **后续启动** | 0 MB | 镜像已缓存 ✅ |

### 资源占用

| 指标 | 预装镜像方式 |
|------|------------|
| **镜像大小** | 800MB (vscode) |
| **启动 CPU** | 低 (直接启动) |
| **启动内存** | 512MB-1GB |
| **磁盘 I/O** | 低 (读取配置) |

---

## 技术优势

### K8s Gitspace 特性

- ✅ **code-server 预装** - 唯一支持方式
- ✅ **快速启动** - 30-60秒就绪
- ✅ **开箱即用** - 无需配置
- ✅ **稳定可靠** - 不受网络影响

---

## 访问架构

### Caddy2-k8s 集成

使用 caddy2-k8s 实现动态路由，无需手动管理 Service/Ingress：

**必需的 Labels**:
```yaml
labels:
  gitspace.app.io/managed-by: "caddy"  # 触发 caddy2-k8s 监控
  app: "gitspace"
  gitspace: "{identifier}"
```

**必需的 Annotations**:
```yaml
annotations:
  gitspace.caddy.default.port: "{port}"  # IDE 服务端口，如 "8089"
```

**访问模式**:
- IDE 主域名: `https://{identifier}.{domain}`
- 应用端口: `https://{identifier}-{port}.{domain}` (PortWatcher 自动发现)

**架构优势**:
- ✅ 无需创建 Service/Ingress 资源
- ✅ 直接路由到 Pod IP (低延迟)
- ✅ 自动端口发现和映射
- ✅ 动态证书管理

**参考**: [caddy2-k8s](https://github.com/ysicing/caddy2-k8s)

---

## 扩展性

### 添加新 IDE

1. **创建 Dockerfile**
   ```dockerfile
   FROM ghcr.io/ysicing/gitspace-runtime:base-latest

   # 安装 IDE 特定依赖
   RUN apt-get install -y <dependencies>

   # 预装 IDE
   RUN curl -fsSL <ide-install-script> | sh

   # 复制 IDE 脚本
   COPY <ide>/scripts/ /usr/local/gitspace/scripts/<ide>/
   ```

2. **添加构建任务**
   ```yaml
   # Taskfile.yml
   build-<ide>:
     desc: 构建 <IDE> 镜像
     deps: [build-base]
     cmds:
       - docker build -t {{.REGISTRY}}/{{.PROJECT}}:<ide>-{{.VERSION}} -f <ide>/Dockerfile .
   ```

3. **配置 Gitness 集成**
   ```go
   // 添加配置
   type GitspacePrebuiltImagesConfig struct {
       NewIDE string `envconfig:"GITSPACE_PREBUILT_IMAGE_NEWIDE" default:"newide-latest"`
   }

   // 添加镜像选择
   case enum.IDETypeNewIDE:
       return o.config.Gitspace.Container.PrebuiltImages.NewIDE
   ```

### VSCode 扩展配置

**环境变量方式**:
```bash
VSCODE_EXTENSIONS="ext1,ext2,ext3" task build-vscode
```

**Taskfile 配置**:
```yaml
vars:
  VSCODE_EXTENSIONS: "ms-python.python,golang.go,esbenp.prettier-vscode"
```

**Dockerfile 构建参数**:
```dockerfile
ARG VSCODE_EXTENSIONS=""
RUN for ext in $(echo "${VSCODE_EXTENSIONS}" | tr ',' ' '); do \
        code-server --install-extension "${ext}"; \
    done
```

---

## 故障排查

### 常见问题

#### 1. 启动时间慢

**检查**:
```bash
# 验证使用了预装镜像
kubectl get pod -n gitspace -o yaml | grep image:
# 应该看到: ghcr.io/ysicing/gitspace-runtime:vscode-latest

# 检查日志不应有下载行为
kubectl logs -n gitspace <pod> | grep -i download
# 不应该看到 "Downloading"
```

#### 2. code-server 未找到

**检查镜像**:
```bash
# 验证镜像内容
docker run --rm ghcr.io/ysicing/gitspace-runtime:vscode-latest code-server --version

# 重新构建和推送
task build-vscode
task push-vscode
```

#### 3. 持久化数据丢失

**检查挂载**:
```bash
kubectl exec -n gitspace <pod> -- mount | grep /home/vscode
# 应该看到 PVC 挂载

# 检查符号链接
kubectl exec -n gitspace <pod> -- ls -la /workspaces
# 应该看到: /workspaces -> /home/vscode
```

---

## 安全考虑

### 镜像安全

- ✅ 使用官方 Ubuntu 24.04 LTS 基础镜像
- ✅ 定期更新依赖包
- ✅ 最小化安装 (只安装必要组件)
- ✅ 非 root 用户运行 (vscode:1000:1000)

### 权限管理

```dockerfile
# 创建非 root 用户
RUN useradd -m -u 1000 -s /bin/bash vscode

# 设置目录权限
RUN chown -R vscode:vscode /home/vscode /usr/local/gitspace

# 切换用户
USER vscode
```

### 网络安全

- ✅ 不暴露不必要的端口
- ✅ 支持 TLS/SSL 配置
- ✅ 可集成认证系统

---

## 参考资源

### 项目链接

- **项目位置**: `gitness/hack/gitspace-runtime`
- **镜像仓库**: `ghcr.io/ysicing/gitspace-runtime`

### 命令参考

```bash
# 构建
task build-all

# 测试
task test-all

# 推送
task push-all

# 多平台
task buildx-all

# 查看所有任务
task --list
```

### 相关文档

- [使用指南](./usage-guide.md) - 详细的使用说明
- [Gitness 集成](./gitness-integration-plan.md) - Gitness 集成方案

---

**文档版本**: v1.0
**最后更新**: 2025-11-06
**维护者**: Gitness Team, @ysicing
