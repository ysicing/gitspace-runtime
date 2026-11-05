# Gitspace Runtime

为 Gitness 的 Kubernetes 开发环境提供预装 IDE 镜像，统一通过 `/usr/local/bin/gitspace-run.sh` 启动。工作区 PVC 挂载到 `/home/vscode`，仓库位于 `/home/vscode/$REPO_NAME`。

## 镜像

默认构建仓库为 `ghcr.io/ysicing/gitspace-runtime`。

| 标签 | 用途 | 默认端口 |
| --- | --- | --- |
| `base-latest` | 通用工具、Git、Node.js 和共享脚本 | — |
| `vscode-latest` | VSCode Desktop，通过 Remote-SSH 连接 | 8088 |
| `vscode-web-latest` | 浏览器 code-server | 8089 |
| `cursor-latest` | Cursor / Windsurf，通过 Remote-SSH 连接 | 8098 / 8099 |
| `intellij-latest` | IntelliJ IDEA，通过 JetBrains Gateway 连接 | 8090 |
| `goland-latest` | GoLand | 8091 |
| `pycharm-latest` | PyCharm | 8092 |
| `webstorm-latest` | WebStorm | 8093 |
| `clion-latest` | CLion | 8094 |
| `phpstorm-latest` | PHPStorm | 8095 |
| `rubymine-latest` | RubyMine | 8096 |
| `rider-latest` | Rider | 8097 |

JetBrains IDE 安装在 `/opt/jetbrains`。启动时为 Gitness Gateway 的固定路径 `$HOME/.cache/JetBrains/RemoteDev/dist/$IDE_TYPE` 建立链接；已有真实目录不会被覆盖。

Web 镜像每次初始化都把镜像中的缺失扩展版本补充到 HOME，保留已有版本、用户配置及扩展删除记录；升级镜像后也会继续补齐。`~/.config/code-server/config.yaml` 保留原内容，启动时另生成仅服务使用的配置，统一监听地址、密码认证及 HOME 内的数据目录。平台访问密码仍通过环境变量传入。

`postCreateCommand` 每个容器成功执行一次，容器重建后重新执行，`postStartCommand` 每次启动都执行。初始化命令应能处理 PVC 中已有的仓库和用户数据。系统依赖优先安装在镜像中，用户自行安装的工具应放在 HOME；手工安装到 `/usr/local`、`/opt` 等容器目录的内容不会随 PVC 保留。不要将 `TMPDIR` 指向 PVC，否则初始化标记也会持久化。

Desktop VSCode、Cursor 和 Windsurf 的远端 Server 由对应客户端安装到 HOME 后随 PVC 保留；客户端升级仍可能安装新版本。本项目尚未预装这些客户端对应的 Server。

## 依赖更新

每次镜像构建都获取安装时的最新版本：

- 基础系统使用 `mcr.microsoft.com/devcontainers/base:ubuntu`，apt 安装发行版仓库中的最新软件包。
- Node.js 使用 NodeSource 的 `setup_lts.x`，自动跟随最新 LTS。
- Claude Code、Codex CLI、Gemini CLI 使用 npm 的 `@latest`。
- code-server 使用官方安装脚本获取最新稳定版。
- JetBrains 使用各产品的 `latest` 下载入口，IntelliJ IDEA / PyCharm 使用统一发行版产品代码 `IIU` / `PCP`。

Taskfile 的所有镜像构建都带 `--pull --no-cache`，重新拉取基础镜像并执行安装，避免安装层缓存保留旧版本。构建时会输出实际安装版本，安装失败立即中止。重建会重新下载软件；已有容器中的工具通过重新构建、发布和更新容器完成升级。

JetBrains 远程开发及专业功能仍受对应产品的授权条款限制。

## 本地验证

需要 Bash、Git、jq、Python 3、Node.js、js-yaml 和 ssh-keygen，ShellCheck 可选。运行时复用 code-server 自带的 js-yaml；本地测试需保证 Node.js 能解析该模块，可安装到临时目录后通过 `NODE_PATH` 指定。安装 Task 后还会验证实际构建命令、缓存刷新及 base 失败时的中止行为；未安装时跳过这部分测试。

```bash
task test
# 或
bash verify-consistency.sh
```

测试使用临时 HOME、本地 Git 仓库和模拟服务，不连接集群、不构建或推送镜像。真实 IDE、sshd 登录和 Kubernetes PVC 行为仍需部署后验证。

## 构建与推送

**现有 `build-*` 任务均带 `--push`，会直接推送镜像。** 基础脚本变化后先发布 base，再依次重建需要的子镜像。单独执行子镜像任务不会自动重建 base。

GitHub Actions 先运行检查，再重新构建并发布 base，最后以最多两个并发任务构建各 IDE。IDE 使用当轮刚发布的 base digest，共享脚本、依赖和 Taskfile 变化会触发完整流程；多轮工作流串行发布。

```bash
task --list
task build-base
task build-vscode-web
task build-vscode
task build-cursor
task build-goland

# 按顺序构建并推送全部镜像
task build-all

# 使用自己的仓库
task build-base REGISTRY=registry.example.com/team/gitspace-runtime
task build-vscode-web REGISTRY=registry.example.com/team/gitspace-runtime

# 自定义 Web 扩展
task build-vscode-web VSCODE_EXTENSIONS=ms-python.python,golang.go
```

base 同时发布 `base-latest`、`base-<构建时间>` 和 `base-<commit>` 标签，CI 使用完整 commit SHA。子 Dockerfile 和 Taskfile 均支持 `BASE_IMAGE`。默认目标平台是 `linux/amd64`；JetBrains 下载步骤目前使用 Linux x64 安装包，不应直接将它用于 ARM 构建。

仅在本机构建而不推送时，可直接使用 Docker：

```bash
docker build --pull --no-cache -f base/Dockerfile -t gitspace-runtime:base-local .
docker build --no-cache -f vscode-web/Dockerfile \
  --build-arg BASE_IMAGE=gitspace-runtime:base-local \
  -t gitspace-runtime:web-local .
```

Web 镜像支持构建时预装扩展。Desktop 镜像中的 `VSCODE_EXTENSIONS` 仅创建扩展目录，实际扩展由 Remote-SSH 客户端安装。

## Gitness 配置

Gitness 默认镜像仓库与本项目默认构建仓库不同，发布后需配置实际地址，例如：

```bash
GITNESS_KUBERNETES_GITSPACE_IMAGE_VSCODE=ghcr.io/ysicing/gitspace-runtime:vscode-latest
GITNESS_KUBERNETES_GITSPACE_IMAGE_VSCODE_WEB=ghcr.io/ysicing/gitspace-runtime:vscode-web-latest
GITNESS_KUBERNETES_GITSPACE_IMAGE_CURSOR=ghcr.io/ysicing/gitspace-runtime:cursor-latest
GITNESS_KUBERNETES_GITSPACE_IMAGE_GOLAND=ghcr.io/ysicing/gitspace-runtime:goland-latest
```

其余 JetBrains 产品使用对应的 `GITNESS_KUBERNETES_GITSPACE_IMAGE_<IDE>` 配置项。Gitness 为实际 IDE 端口配置 TCP startup/readiness 探针，启动探针允许约 10 分钟完成克隆和初始化；未监听端口前 Pod 不就绪。

## 启动契约

| 变量 | 含义 |
| --- | --- |
| `HOME` / `WORKSPACE_DIR` | Gitness 统一设置为 `/home/vscode` |
| `REPO_URL` / `REPO_NAME` / `BRANCH` | 克隆地址、HOME 下的仓库名和初次克隆分支 |
| `IDE_TYPE` | Gitness IDE 标识，如 `vs_code`、`vs_code_web`、`goland` |
| `IDE_PORT` / `SSH_PORT` | Web / SSH 监听端口，由 Gitness 指定 |
| `GITSPACE_ACCESS_KEY` | Web 登录密码；SSH 密码模式的用户密码 |
| `GITSPACE_ACCESS_TYPE` | `user_credentials`、`ssh_key` 或 `combined` |
| `SSH_PUBLIC_KEY` | SSH 公钥，可以包含多行 |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | Git 提交身份 |
| `GITSPACE_POST_CREATE_COMMAND` | 内部变量，保留原始 JSON 的 postCreateCommand |
| `GITSPACE_POST_START_COMMAND` | 内部变量，保留原始 JSON 的 postStartCommand |

Web 必须提供非空访问密钥，code-server 开启密码认证。密码通过进程环境传递，不写入 code-server 配置文件或启动日志。SSH 密码模式必须提供密钥，公钥模式必须提供公钥，`combined` 允许两种方式分别登录；所有模式均禁止空密码。

SSH Host Key 在首次启动时生成，保存在 PVC 的 `$HOME/.gitspace/ssh-host-keys` 中，重启复用。升级旧环境后首次连接会看到新的 SSH 主机指纹，应核实后更新客户端 known_hosts。

SSH 初始化会移除 HOME 目录本身的组和其他用户写权限，避免已有 PVC 的宽松权限导致 OpenSSH StrictModes 拒绝公钥认证；保留其他权限，不递归修改项目文件或子目录，也不关闭 StrictModes。

已有仓库在重启时仅更新 origin，以同步新的仓库凭证；保留当前分支、未提交修改和未跟踪文件，不自动 pull/reset。每次启动不再递归 chown 整个 HOME；旧数据内部若已有错误权限，应单独修复。

Gitness 传递 devcontainer 普通容器环境变量，重复项以最后一项为准；仓库、访问凭证、端口、HOME 和 `GITSPACE_*` 内部变量由平台控制。postCreateCommand 在当前容器中每个仓库首次成功后记录完成标记，失败可重试；postStartCommand 每次启动执行。支持字符串、参数数组和并行对象形式，任一命令失败都会阻止 IDE 启动。完成标记位于容器临时目录的 `gitspace-lifecycle-<UID>/`，旧 PVC 中的 Git 目录标记不再用于跳过初始化。

目前 Kubernetes 使用预装 IDE 镜像，devcontainer 的自定义镜像、Features 以及其他生命周期阶段不在本次支持范围内。
