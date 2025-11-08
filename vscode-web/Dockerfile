# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace VSCode 专用镜像
# 基于 base 镜像，添加 VSCode Server 支持

FROM ghcr.io/ysicing/gitspace-runtime:base-latest

ARG VSCODE_EXTENSIONS=""

LABEL maintainer="Gitness Team"
LABEL description="Gitspace VSCode Web image with code-server support"

USER root

# 安装 VSCode 特定依赖
RUN apt-get update && apt-get install -y \
    # 构建工具（code-server 需要）
    build-essential \
    # Python 支持（常用）
    python3 python3-pip \
    # Node.js 和 npm 已在 base 镜像中安装
    # 清理
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ✅ 预装 code-server（在镜像构建时安装最新版，避免运行时下载）
RUN echo "Installing latest code-server..." \
    && curl -fsSL https://code-server.dev/install.sh | sh \
    && code-server --version \
    && echo "✓ code-server pre-installed successfully"

# 复制 VSCode Web 专用脚本
COPY vscode-web/scripts/*.sh /usr/local/gitspace/scripts/vscode/
RUN chmod +x /usr/local/gitspace/scripts/vscode/*.sh

# 复制脚本到系统路径
COPY vscode-web/gitspace-init.sh /usr/local/bin/gitspace-init.sh
COPY vscode-web/gitspace-run.sh /usr/local/bin/gitspace-run.sh
RUN chmod +x /usr/local/bin/gitspace-init.sh /usr/local/bin/gitspace-run.sh

# 创建预构建配置目录（在安全位置，不会被 PVC 覆盖）
RUN mkdir -p /opt/gitspace-vscode/.config/code-server \
    /opt/gitspace-vscode/.local/share/code-server \
    && chown -R vscode:vscode /opt/gitspace-vscode/.config /opt/gitspace-vscode/.local

# 切换到 vscode 用户（在安装扩展前切换）
USER vscode

# 预装 VSCode 扩展到预构建目录
RUN if [ -n "${VSCODE_EXTENSIONS}" ]; then \
        echo "Installing VSCode extensions: ${VSCODE_EXTENSIONS}"; \
        for ext in $(echo "${VSCODE_EXTENSIONS}" | tr ',' ' '); do \
            echo "Installing extension: ${ext}"; \
            code-server --install-extension "${ext}" \
                --extensions-dir "/opt/gitspace-vscode/.local/share/code-server/extensions/" \
                || echo "Failed to install: ${ext}"; \
        done; \
        echo "✓ Extensions installed to /opt/gitspace-vscode/.local/share/code-server/extensions/"; \
    else \
        echo "No extensions specified, skipping extension installation"; \
    fi

# 切换回 root 以便后续操作
USER root


# 健康检查：检查 code-server 命令是否可用（安装后）
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD [ "which", "git" ]

CMD ["sleep", "infinity"]
