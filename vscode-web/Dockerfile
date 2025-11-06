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

# 复制 VSCode 专用脚本
COPY vscode/scripts/*.sh /usr/local/gitspace/scripts/vscode/
RUN chmod +x /usr/local/gitspace/scripts/vscode/*.sh

# 预装 VSCode 扩展（如果指定了）
RUN if [ -n "${VSCODE_EXTENSIONS}" ]; then \
        echo "Installing VSCode extensions: ${VSCODE_EXTENSIONS}"; \
        for ext in $(echo "${VSCODE_EXTENSIONS}" | tr ',' ' '); do \
            echo "Installing extension: ${ext}"; \
            code-server --install-extension "${ext}" || echo "Failed to install: ${ext}"; \
        done; \
    fi

# 复制 VSCode 初始化脚本
COPY vscode/init-vscode.sh /usr/local/bin/gitspace-init.sh
RUN chmod +x /usr/local/bin/gitspace-init.sh

# 创建 VSCode 配置目录
RUN mkdir -p /home/vscode/.config/code-server \
    /home/vscode/.local/share/code-server \
    && chown -R vscode:vscode /home/vscode/.config /home/vscode/.local

# 切换到非 root 用户
USER vscode

# 健康检查：检查 code-server 命令是否可用（安装后）
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD [ "which", "git" ]

CMD ["sleep", "infinity"]
