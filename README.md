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

## 本地验证

需要 Bash、Git、jq、Python 3 和 ssh-keygen，ShellCheck 可选。

```bash
task test
# 或
bash verify-consistency.sh
```

测试使用临时 HOME、本地 Git 仓库和模拟服务，不连接集群、不构建或推送镜像。真实 IDE、sshd 登录和 Kubernetes PVC 行为仍需部署后验证。

## 构建与推送

**现有 `build-*` 任务均带 `--push`，会直接推送镜像。** 基础脚本变化后先发布 base，再依次重建需要的子镜像。单独执行子镜像任务不会自动重建 base。

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

子 Dockerfile 支持 `BASE_IMAGE`。默认目标平台是 `linux/amd64`；JetBrains 下载步骤目前使用 Linux x64 安装包，不应直接将它用于 ARM 构建。

仅在本机构建而不推送时，可直接使用 Docker：

```bash
docker build -f base/Dockerfile -t gitspace-runtime:base-local .
docker build -f vscode-web/Dockerfile \
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

已有仓库在重启时仅更新 origin，以同步新的仓库凭证；保留当前分支、未提交修改和未跟踪文件，不自动 pull/reset。每次启动不再递归 chown 整个 HOME；旧数据内部若已有错误权限，应单独修复。

Gitness 传递 devcontainer 普通容器环境变量，重复项以最后一项为准；仓库、访问凭证、端口、HOME 和 `GITSPACE_*` 内部变量由平台控制。postCreateCommand 在仓库中首次成功后记录完成标记，失败可重试；postStartCommand 每次启动执行。支持字符串、参数数组和并行对象形式，任一命令失败都会阻止 IDE 启动。完成标记位于 Git 目录的 `gitspace-post-create-complete`。

目前 Kubernetes 使用预装 IDE 镜像，devcontainer 的自定义镜像、Features 以及其他生命周期阶段不在本次支持范围内。
