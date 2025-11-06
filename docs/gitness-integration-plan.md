# Gitness 创建 Gitspace 适配预装镜像方案

**日期**: 2025-11-05
**目标**: 使 Gitness 在创建 K8s Gitspace 时使用预装镜像,实现开箱即用

---

## 当前架构分析

### 现有流程

```
用户调用 CreateGitspace API
  ↓
Controller.Create() (create.go)
  ├─ 创建 GitspaceConfig
  └─ 返回配置
  ↓
用户调用 StartGitspace API
  ↓
KubernetesOrchestrator.CreateAndStartGitspace()
  ├─ Step 1: 创建 Deployment
  │   ├─ 使用基础镜像 (如 mcr.microsoft.com/devcontainers/base:ubuntu)
  │   └─ InitContainer: 空
  ├─ Step 2: Pod 启动后,在容器内执行:
  │   ├─ ValidateSupportedOS()
  │   ├─ manageUser()
  │   ├─ setEnvironment()
  │   ├─ installTools() ← ⚠️ 运行时下载 IDE
  │   ├─ InstallGit()
  │   ├─ SetupGitCredentials()
  │   ├─ CloneCode()
  │   ├─ IDE.Setup() ← ⚠️ 安装 code-server
  │   └─ IDE.Run() ← 启动 IDE
  └─ Step 3: 等待就绪
```

**问题**:
1. ❌ 使用基础镜像 (未预装 IDE)
2. ❌ 运行时通过脚本下载和安装 IDE
3. ❌ 启动时间长 (3-5 分钟)

---

## 目标架构

### 期望流程

```
用户调用 CreateGitspace API
  ↓
Controller.Create() (create.go)
  ├─ 创建 GitspaceConfig
  └─ 返回配置
  ↓
用户调用 StartGitspace API
  ↓
KubernetesOrchestrator.CreateAndStartGitspace()
  ├─ Step 1: 创建 Deployment
  │   ├─ 使用预装镜像 ✅ (ghcr.io/ysicing/gitspace-runtime:vscode-latest)
  │   └─ InitContainer: 执行初始化脚本
  │       ├─ CloneCode()
  │       ├─ SetupGitCredentials()
  │       └─ manageUser() (可选)
  ├─ Step 2: Pod 启动后,在主容器:
  │   ├─ ✅ code-server 已预装,直接启动!
  │   └─ IDE.Run() ← 快速启动
  └─ Step 3: 等待就绪 (30-60秒)
```

**优势**:
1. ✅ 使用预装镜像 (code-server 已内置)
2. ✅ 跳过运行时下载和安装步骤
3. ✅ 启动时间缩短至 30-60 秒

---

## 需要修改的代码

### 1. 镜像选择逻辑 ⭐⭐⭐

**文件**: `app/gitspace/orchestrator/container/kubernetes_orchestrator.go`

**当前代码** (line ~500):
```go
// getDefaultBaseImage 返回默认基础镜像
func (o *KubernetesOrchestrator) getDefaultBaseImage() string {
    return "mcr.microsoft.com/devcontainers/base:ubuntu"
}
```

**需要修改为**:
```go
// getDefaultBaseImage 根据 IDE 类型返回对应的预装镜像
func (o *KubernetesOrchestrator) getDefaultBaseImage(ide enum.IDEType) string {
    switch ide {
    case enum.IDETypeVSCodeWeb, enum.IDETypeVSCode:
        // 使用预装 code-server 的镜像
        return o.config.Gitspace.Container.PrebuiltImages.VSCode
    case enum.IDETypeCursor:
        return o.config.Gitspace.Container.PrebuiltImages.Cursor
    case enum.IDETypeWindsurf:
        return o.config.Gitspace.Container.PrebuiltImages.Windsurf
    case enum.IDETypeIntelliJ, enum.IDETypePyCharm, enum.IDETypeGoland,
         enum.IDETypeWebStorm, enum.IDETypeCLion, enum.IDETypePHPStorm,
         enum.IDETypeRubyMine, enum.IDETypeRider:
        return o.config.Gitspace.Container.PrebuiltImages.JetBrains
    default:
        // 降级到基础镜像
        return "mcr.microsoft.com/devcontainers/base:ubuntu"
    }
}
```

**调用点修改** (line ~600):
```go
// 旧代码
imageName := o.getDefaultBaseImage()

// 新代码
imageName := o.getDefaultBaseImage(gitspaceConfig.GitspaceInstance.Identifier.IDE)
```

---

### 2. 配置文件扩展 ⭐⭐⭐

**文件**: `types/config.go`

**添加预装镜像配置**:
```go
type GitspaceConfig struct {
    Container GitspaceContainerConfig
    // ... 其他配置
}

type GitspaceContainerConfig struct {
    // 新增: 预装镜像配置
    PrebuiltImages GitspacePrebuiltImagesConfig

    // 现有配置
    DefaultBaseImage string
    // ...
}

type GitspacePrebuiltImagesConfig struct {
    // 是否启用预装镜像
    Enabled bool `envconfig:"GITSPACE_PREBUILT_IMAGES_ENABLED" default:"true"`

    // 镜像仓库前缀
    Registry string `envconfig:"GITSPACE_PREBUILT_IMAGES_REGISTRY" default:"ghcr.io/ysicing/gitspace-runtime"`

    // 各 IDE 的镜像标签
    VSCode     string `envconfig:"GITSPACE_PREBUILT_IMAGE_VSCODE" default:"vscode-latest"`
    Cursor     string `envconfig:"GITSPACE_PREBUILT_IMAGE_CURSOR" default:"cursor-latest"`
    Windsurf   string `envconfig:"GITSPACE_PREBUILT_IMAGE_WINDSURF" default:"windsurf-latest"`
    JetBrains  string `envconfig:"GITSPACE_PREBUILT_IMAGE_JETBRAINS" default:"jetbrains-latest"`
}
```

**环境变量示例** (`.env`):
```bash
# 启用预装镜像
GITSPACE_PREBUILT_IMAGES_ENABLED=true

# 镜像仓库
GITSPACE_PREBUILT_IMAGES_REGISTRY=ghcr.io/ysicing/gitspace-runtime

# 各 IDE 镜像标签
GITSPACE_PREBUILT_IMAGE_VSCODE=vscode-v4.23.1
GITSPACE_PREBUILT_IMAGE_CURSOR=cursor-latest
GITSPACE_PREBUILT_IMAGE_WINDSURF=windsurf-latest
GITSPACE_PREBUILT_IMAGE_JETBRAINS=jetbrains-2024.1
```

---

### 3. 安装步骤优化 ⭐⭐

**文件**: `app/gitspace/orchestrator/container/kubernetes_steps.go`

**当前逻辑** (buildSetupSteps):
```go
steps := []KubernetesStep{
    {Name: "Validate OS", Execute: ValidateSupportedOS, StopOnFailure: true},
    {Name: "Manage User", Execute: manageUser, StopOnFailure: false},
    {Name: "Set Environment", Execute: setEnvironment, StopOnFailure: false},
    {Name: "Install Tools", Execute: installTools, StopOnFailure: true},  // ← 下载 IDE
    {Name: "Install Git", Execute: InstallGit, StopOnFailure: true},
    {Name: "Setup Git Credentials", Execute: SetupGitCredentials, StopOnFailure: false},
    {Name: "Clone Code", Execute: CloneCode, StopOnFailure: true},
    {Name: "IDE Setup", Execute: IDE.Setup, StopOnFailure: true},  // ← 安装 code-server
    {Name: "IDE Run", Execute: IDE.Run, StopOnFailure: true},
}
```

**优化后逻辑**:
```go
func (o *KubernetesOrchestrator) buildSetupSteps(
    ctx context.Context,
    gitspaceContext *types.GitspaceContext,
    // ...
) []KubernetesStep {
    // 检查是否使用预装镜像
    isPrebuilt := o.isUsingPrebuiltImage(gitspaceContext.ImageName)

    steps := []KubernetesStep{
        {Name: "Validate OS", Execute: ValidateSupportedOS, StopOnFailure: true},
        {Name: "Manage User", Execute: manageUser, StopOnFailure: false},
        {Name: "Set Environment", Execute: setEnvironment, StopOnFailure: false},
    }

    // 只在非预装镜像时安装工具
    if !isPrebuilt {
        steps = append(steps, KubernetesStep{
            Name:          "Install Tools",
            Execute:       installTools,
            StopOnFailure: true,
        })
    }

    steps = append(steps, []KubernetesStep{
        {Name: "Install Git", Execute: InstallGit, StopOnFailure: true},
        {Name: "Setup Git Credentials", Execute: SetupGitCredentials, StopOnFailure: false},
        {Name: "Clone Code", Execute: CloneCode, StopOnFailure: true},
    }...)

    // 只在非预装镜像时执行 IDE 安装
    if !isPrebuilt {
        steps = append(steps, KubernetesStep{
            Name:          "IDE Setup",
            Execute:       IDE.Setup,
            StopOnFailure: true,
        })
    } else {
        // 预装镜像: 验证 IDE 已存在
        steps = append(steps, KubernetesStep{
            Name:          "Verify IDE",
            Execute:       o.verifyPreinstalledIDE,
            StopOnFailure: false,
        })
    }

    steps = append(steps, KubernetesStep{
        Name:          "IDE Run",
        Execute:       IDE.Run,
        StopOnFailure: true,
    })

    return steps
}

// 新增: 检查是否使用预装镜像
func (o *KubernetesOrchestrator) isUsingPrebuiltImage(imageName string) bool {
    if !o.config.Gitspace.Container.PrebuiltImages.Enabled {
        return false
    }

    registry := o.config.Gitspace.Container.PrebuiltImages.Registry
    return strings.HasPrefix(imageName, registry)
}

// 新增: 验证预装 IDE
func (o *KubernetesOrchestrator) verifyPreinstalledIDE(
    ctx context.Context,
    podExec *KubernetesPodExec,
    gitspaceLogger gitspaceTypes.GitspaceLogger,
    gitspaceContext *types.GitspaceContext,
) error {
    gitspaceLogger.Info("验证 IDE 已预装...")

    // 检查 code-server 是否存在
    script := "command -v code-server && code-server --version"
    output, err := podExec.ExecuteCommand(ctx, script, false)
    if err != nil {
        gitspaceLogger.Warn("IDE 未预装,将回退到安装模式")
        return nil // 不阻塞流程
    }

    gitspaceLogger.Info(fmt.Sprintf("✓ IDE 已预装: %s", output))
    return nil
}
```

---

### 4. IDE 运行逻辑调整 ⭐⭐

**文件**: `app/gitspace/orchestrator/ide/vscodeweb.go`

**当前 Run() 方法**:
```go
func (v *VSCodeWeb) Run(
    ctx context.Context,
    devcontainer *devcontainer.Exec,
    gitspaceLogger gitspaceTypes.GitspaceLogger,
) error {
    // 生成并执行 run_vscode_web.sh
    runScript, _ := GenerateScriptFromTemplate("run_vscode_web.sh", data)
    return devcontainer.ExecuteCommandInHomeDirAndLog(ctx, runScript, false, gitspaceLogger, true)
}
```

**优化后 (支持预装镜像)**:
```go
func (v *VSCodeWeb) Run(
    ctx context.Context,
    devcontainer *devcontainer.Exec,
    gitspaceLogger gitspaceTypes.GitspaceLogger,
    isPrebuilt bool,  // 新增参数
) error {
    if isPrebuilt {
        // 预装镜像: 直接启动,无需等待下载
        gitspaceLogger.Info("使用预装的 code-server,快速启动...")

        startScript := fmt.Sprintf(`
#!/bin/bash
set -e

# 配置 code-server
mkdir -p "$HOME/.config/code-server"
cat > "$HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 0.0.0.0:%d
auth: none
cert: false
EOF

# 设置代理 URI
if [ -n "%s" ]; then
  export VSCODE_PROXY_URI="%s"
fi

# 直接启动 (code-server 已预装)
cd "$HOME/%s" 2>/dev/null || cd "$HOME"
exec code-server --disable-workspace-trust .
`, v.port, v.proxyURI, v.proxyURI, v.repoName)

        return devcontainer.ExecuteCommandInHomeDirAndLog(ctx, startScript, false, gitspaceLogger, true)
    }

    // 非预装镜像: 使用原有逻辑 (包含下载和等待)
    runScript, _ := GenerateScriptFromTemplate("run_vscode_web.sh", data)
    return devcontainer.ExecuteCommandInHomeDirAndLog(ctx, runScript, false, gitspaceLogger, true)
}
```

---

### 5. Deployment 生成调整 ⭐

**文件**: `app/gitspace/orchestrator/container/kubernetes_orchestrator.go`

**当前 Deployment 生成** (createDeployment):
```go
deployment := &appsv1.Deployment{
    Spec: appsv1.DeploymentSpec{
        Template: corev1.PodTemplateSpec{
            Spec: corev1.PodSpec{
                InitContainers: []corev1.Container{},  // 空
                Containers: []corev1.Container{
                    {
                        Name:  "gitspace",
                        Image: imageName,  // 基础镜像
                        // ...
                    },
                },
            },
        },
    },
}
```

**优化后 (添加 InitContainer)**:
```go
func (o *KubernetesOrchestrator) createDeployment(
    ctx context.Context,
    gitspaceContext *types.GitspaceContext,
) (*appsv1.Deployment, error) {
    imageName := gitspaceContext.ImageName
    isPrebuilt := o.isUsingPrebuiltImage(imageName)

    podSpec := corev1.PodSpec{
        Containers: []corev1.Container{
            {
                Name:  "gitspace",
                Image: imageName,
                // ...
            },
        },
    }

    // 如果使用预装镜像,添加 InitContainer
    if isPrebuilt {
        initContainer := o.buildInitContainer(gitspaceContext, imageName)
        podSpec.InitContainers = []corev1.Container{initContainer}
    }

    deployment := &appsv1.Deployment{
        Spec: appsv1.DeploymentSpec{
            Template: corev1.PodTemplateSpec{
                Spec: podSpec,
            },
        },
    }

    return deployment, nil
}

// 新增: 构建 InitContainer
func (o *KubernetesOrchestrator) buildInitContainer(
    gitspaceContext *types.GitspaceContext,
    imageName string,
) corev1.Container {
    return corev1.Container{
        Name:  "gitspace-init",
        Image: imageName,  // 使用同一预装镜像
        Command: []string{"/bin/bash", "-c"},
        Args: []string{`
set -euo pipefail

echo "=========================================="
echo "Gitspace 初始化 (使用预装镜像)"
echo "=========================================="

# 检查 code-server 是否预装
if command -v code-server &> /dev/null; then
    echo "✓ code-server: $(code-server --version | head -1)"
fi

# 使用镜像内置脚本初始化
if [ -f /usr/local/bin/gitspace-init.sh ]; then
    /usr/local/bin/gitspace-init.sh
fi

echo "✓ 初始化完成"
`},
        Env: o.buildInitEnv(gitspaceContext),
        VolumeMounts: []corev1.VolumeMount{
            {
                Name:      "home",
                MountPath: "/home/vscode",
            },
        },
        SecurityContext: &corev1.SecurityContext{
            RunAsUser: ptr.Int64(0),  // Root for init
        },
    }
}
```

---

## 实施计划

### Phase 1: 配置和镜像选择 (高优先级)

**文件修改**:
1. ✅ `types/config.go` - 添加预装镜像配置
2. ✅ `kubernetes_orchestrator.go` - 修改 `getDefaultBaseImage()`

**测试**:
```bash
# 设置环境变量
export GITSPACE_PREBUILT_IMAGES_ENABLED=true
export GITSPACE_PREBUILT_IMAGES_REGISTRY=ghcr.io/ysicing/gitspace-runtime

# 创建 Gitspace
curl -X POST http://localhost:3000/api/v1/spaces/{space}/gitspaces \
  -d '{"ide": "vscode_web", "code_repo_url": "https://github.com/example/repo.git"}'

# 验证使用的镜像
kubectl get deployment -n gitness -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
# 预期: ghcr.io/ysicing/gitspace-runtime:vscode-latest
```

### Phase 2: 步骤优化 (中优先级)

**文件修改**:
1. ✅ `kubernetes_steps.go` - 条件跳过安装步骤
2. ✅ `vscodeweb.go` - 快速启动逻辑

**测试**:
```bash
# 创建 Gitspace 并查看日志
kubectl logs -n gitness <pod-name> -f

# 验证是否跳过安装
# 预期看到: "验证 IDE 已预装" 而不是 "Install Tools"
```

### Phase 3: InitContainer 集成 (低优先级,可选)

**文件修改**:
1. ✅ `kubernetes_orchestrator.go` - 添加 InitContainer

**收益**: 进一步缩短启动时间

---

## 向后兼容性

### 降级策略

如果预装镜像不可用,自动降级到原有逻辑:

```go
func (o *KubernetesOrchestrator) getDefaultBaseImage(ide enum.IDEType) string {
    // 检查是否启用预装镜像
    if !o.config.Gitspace.Container.PrebuiltImages.Enabled {
        return "mcr.microsoft.com/devcontainers/base:ubuntu"
    }

    // 尝试使用预装镜像
    prebuiltImage := o.getPrebuiltImage(ide)

    // 验证镜像是否存在
    if o.validateImage(prebuiltImage) {
        return prebuiltImage
    }

    // 降级到基础镜像
    log.Warn("预装镜像不可用,降级到基础镜像")
    return "mcr.microsoft.com/devcontainers/base:ubuntu"
}
```

### 配置开关

```bash
# 禁用预装镜像 (使用原有逻辑)
export GITSPACE_PREBUILT_IMAGES_ENABLED=false
```

---

## 文件修改清单

| 文件 | 修改类型 | 优先级 |
|------|---------|-------|
| `types/config.go` | 新增配置结构 | ⭐⭐⭐ 高 |
| `kubernetes_orchestrator.go` | 修改镜像选择逻辑 | ⭐⭐⭐ 高 |
| `kubernetes_steps.go` | 条件跳过安装步骤 | ⭐⭐ 中 |
| `vscodeweb.go` | 快速启动逻辑 | ⭐⭐ 中 |
| `kubernetes_orchestrator.go` | 添加 InitContainer | ⭐ 低 (可选) |

---

## 预期收益

### 启动时间对比

| 场景 | 当前 | 优化后 | 提升 |
|------|-----|--------|------|
| **首次启动** | 3-5 分钟 | 30-60 秒 | **5-10倍** |
| **后续启动** | 3-5 分钟 | 15-30 秒 | **10-20倍** |

### 用户体验提升

- ✅ 快速就绪 (30-60秒)
- ✅ 离线可用 (无需网络下载)
- ✅ 稳定可靠 (不受网络波动影响)

---

## 下一步

1. **修改代码**: 按照上述方案修改 Gitness 代码
2. **构建镜像**:
   ```bash
   cd /Users/ysicing/Work/github/ysicing/gitspace-runtime
   make build-all && make push-all
   ```
3. **配置环境变量**: 在 Gitness 中启用预装镜像
4. **测试验证**: 创建 Gitspace 并验证启动时间

---

**报告时间**: 2025-11-05
**版本**: v1.0
