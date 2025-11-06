# JetBrains 镜像构建指南

## 概述

通过统一的 Dockerfile 和构建参数，可以构建出所有 JetBrains IDE 的专用镜像。每个 IDE 使用独立的镜像，预安装对应的 IDE 产品。

---

## 支持的 IDE 产品

| IDE | 产品代码 | 镜像名称 | 端口 | 用途 |
|-----|---------|---------|------|------|
| IntelliJ IDEA Community | `IIC` | `intellij-latest` | 8090 | Java/Kotlin 开发 |
| GoLand | `GO` | `goland-latest` | 8091 | Go 开发 |
| PyCharm Community | `PCC` | `pycharm-latest` | 8092 | Python 开发 |
| WebStorm | `WS` | `webstorm-latest` | 8093 | JavaScript/TypeScript 开发 |
| CLion | `CL` | `clion-latest` | 8094 | C/C++ 开发 |
| PHPStorm | `PS` | `phpstorm-latest` | 8095 | PHP 开发 |
| RubyMine | `RM` | `rubymine-latest` | 8096 | Ruby 开发 |
| Rider | `RD` | `rider-latest` | 8097 | .NET 开发 |

**注意**: PyCharm 也可使用 Professional 版本，产品代码为 `PCP`

---

## 构建方式

### 方式一：使用 Taskfile（推荐）

#### 构建单个 IDE 镜像
```bash
cd hack/gitspace-runtime

# 构建 IntelliJ IDEA
task build-intellij

# 构建 GoLand
task build-goland

# 构建 PyCharm
task build-pycharm

# 构建 WebStorm
task build-webstorm

# 构建 CLion
task build-clion

# 构建 PHPStorm
task build-phpstorm

# 构建 RubyMine
task build-rubymine

# 构建 Rider
task build-rider
```

#### 构建所有 JetBrains IDE 镜像
```bash
cd hack/gitspace-runtime

# 一次性构建所有 JetBrains IDE 镜像
task build-jetbrains
```

这将依次构建：
1. IntelliJ IDEA → `intellij-latest`
2. GoLand → `goland-latest`
3. PyCharm → `pycharm-latest`
4. WebStorm → `webstorm-latest`
5. CLion → `clion-latest`
6. PHPStorm → `phpstorm-latest`
7. RubyMine → `rubymine-latest`
8. Rider → `rider-latest`

### 方式二：手动 Docker 构建

```bash
cd hack/gitspace-runtime

# 构建 IntelliJ IDEA
docker buildx build \
  --platform linux/amd64 \
  --build-arg IDE_PRODUCT_CODE=IIC \
  --build-arg IDE_NAME=intellij \
  -t hub.51talk.biz/citools/gitspace-runtime:intellij-latest \
  -f jetbrains/Dockerfile \
  --push \
  .

# 构建 GoLand
docker buildx build \
  --platform linux/amd64 \
  --build-arg IDE_PRODUCT_CODE=GO \
  --build-arg IDE_NAME=goland \
  -t hub.51talk.biz/citools/gitspace-runtime:goland-latest \
  -f jetbrains/Dockerfile \
  --push \
  .

# 构建 PyCharm Community
docker buildx build \
  --platform linux/amd64 \
  --build-arg IDE_PRODUCT_CODE=PCC \
  --build-arg IDE_NAME=pycharm \
  -t hub.51talk.biz/citools/gitspace-runtime:pycharm-latest \
  -f jetbrains/Dockerfile \
  --push \
  .
```

---

## 构建参数说明

### 必需参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `IDE_PRODUCT_CODE` | JetBrains 产品代码 | `IIC`, `GO`, `PCC`, `WS` |
| `IDE_NAME` | IDE 名称（用于标识） | `intellij`, `goland`, `pycharm` |

### 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `BUILD_DATE` | 构建日期 | 当前日期 |
| `VCS_REF` | Git commit hash | 当前 commit |
| `BASE_IMAGE` | 基础镜像 | `base-latest` |

---

## 镜像特性

### 预安装内容
- ✅ SSH Server（预配置，端口由环境变量指定）
- ✅ JetBrains IDE（最新版本，自动下载）
- ✅ 必需的系统依赖（图形库、字体等）
- ✅ Git 和基础开发工具

### 镜像大小
- **基础镜像**: ~500MB
- **JetBrains 镜像**: ~1.5GB（包含完整 IDE）
- **构建时间**: 10-15 分钟（每个 IDE）

### 启动性能
- **首次启动**: 30-60 秒（无需下载）
- **后续启动**: 20-30 秒（使用缓存）
- **对比 Docker**: 比运行时下载快 **10x** ⚡

---

## 配置映射

### Kubernetes 配置
每个 IDE 在 `types/config.go` 中都有独立的镜像配置：

```go
IntelliJImage  string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_INTELLIJ" default:"hub.51talk.biz/citools/gitspace-runtime:intellij-latest"`
GolandImage    string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_GOLAND" default:"hub.51talk.biz/citools/gitspace-runtime:goland-latest"`
PyCharmImage   string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_PYCHARM" default:"hub.51talk.biz/citools/gitspace-runtime:pycharm-latest"`
WebStormImage  string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_WEBSTORM" default:"hub.51talk.biz/citools/gitspace-runtime:webstorm-latest"`
CLionImage     string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_CLION" default:"hub.51talk.biz/citools/gitspace-runtime:clion-latest"`
PHPStormImage  string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_PHPSTORM" default:"hub.51talk.biz/citools/gitspace-runtime:phpstorm-latest"`
RubyMineImage  string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_RUBYMINE" default:"hub.51talk.biz/citools/gitspace-runtime:rubymine-latest"`
RiderImage     string `envconfig:"GITNESS_KUBERNETES_GITSPACE_IMAGE_RIDER" default:"hub.51talk.biz/citools/gitspace-runtime:rider-latest"`
```

### 环境变量配置
可以通过环境变量覆盖默认镜像：

```bash
# IntelliJ IDEA
export GITNESS_KUBERNETES_GITSPACE_IMAGE_INTELLIJ=your-registry/intellij:custom

# GoLand
export GITNESS_KUBERNETES_GITSPACE_IMAGE_GOLAND=your-registry/goland:custom

# PyCharm
export GITNESS_KUBERNETES_GITSPACE_IMAGE_PYCHARM=your-registry/pycharm:custom
```

---

## 使用示例

### 创建 Gitspace 时自动选择镜像

当用户创建 Gitspace 并选择 IDE 类型时，系统会自动使用对应的镜像：

```go
// 用户选择 GoLand
IDE: enum.IDETypeGoland

// 系统自动使用 GoLand 镜像
Image: config.Kubernetes.GitspaceImages.GolandImage
// → hub.51talk.biz/citools/gitspace-runtime:goland-latest
```

### JetBrains Gateway 连接

以 GoLand 为例：

```ssh-config
Host gitspace-goland
  HostName gitspace.example.com
  Port 8091
  User vscode
  IdentityFile ~/.ssh/id_rsa
```

连接后，JetBrains Gateway 会自动识别预安装的 GoLand，无需等待下载。

---

## 镜像管理策略

### 版本管理
每次构建会生成两个标签：
- `latest`: 最新版本（推荐用于开发环境）
- `YYYYMMDDHH`: 时间戳版本（推荐用于生产环境）

示例：
```
hub.51talk.biz/citools/gitspace-runtime:intellij-latest
hub.51talk.biz/citools/gitspace-runtime:intellij-2025110616
```

### 更新策略
- **开发环境**: 使用 `latest` 标签，自动获取最新版本
- **生产环境**: 使用时间戳标签，确保版本稳定
- **更新频率**: 建议每月重新构建一次以获取最新 IDE 版本

### 清理旧镜像
```bash
# 列出所有 JetBrains 镜像
docker images | grep jetbrains

# 删除旧版本（保留最近 3 个版本）
docker images | grep "intellij-202" | tail -n +4 | awk '{print $3}' | xargs docker rmi
```

---

## 故障排查

### 构建失败

**问题**: IDE 下载失败
```
curl: (7) Failed to connect to download.jetbrains.com
```

**解决**:
1. 检查网络连接
2. 使用代理：`docker build --build-arg HTTPS_PROXY=http://proxy:8080`
3. 手动下载后使用本地文件

**问题**: 解压失败
```
tar: Unexpected EOF in archive
```

**解决**:
1. 重新构建（可能是下载不完整）
2. 检查磁盘空间

### 镜像过大

**问题**: 镜像大小超过 2GB

**解决**:
- JetBrains IDE 本身约 1GB，这是正常的
- 可以考虑使用多阶段构建进一步优化
- 清理不必要的缓存文件

### 启动慢

**问题**: 容器启动超过 2 分钟

**解决**:
1. 检查是否在使用正确的预安装镜像
2. 检查 SSH Server 启动日志
3. 检查 remote-dev-server 启动日志

---

## JetBrains 产品代码参考

完整的产品代码列表：https://www.jetbrains.com/help/idea/installation-guide.html#toolbox

常用产品代码：
- **IntelliJ IDEA**: `IIC` (Community), `IIU` (Ultimate)
- **PyCharm**: `PCC` (Community), `PCP` (Professional)
- **GoLand**: `GO`
- **WebStorm**: `WS`
- **CLion**: `CL`
- **PHPStorm**: `PS`
- **RubyMine**: `RM`
- **Rider**: `RD`
- **DataGrip**: `DG`
- **AppCode**: `AC`

---

## 最佳实践

1. **镜像命名**: 使用统一的命名规范 `{ide}-{version}`
2. **构建顺序**: 先构建常用 IDE（IntelliJ、GoLand、PyCharm）
3. **并行构建**: 使用 CI/CD 并行构建多个镜像以节省时间
4. **缓存利用**: 保持 base 镜像不变以利用 Docker 缓存
5. **定期更新**: 每月重新构建以获取最新 IDE 版本
6. **镜像扫描**: 使用 Trivy 等工具扫描镜像安全漏洞

---

**创建日期**: 2025-11-06
**维护者**: Gitness Team
