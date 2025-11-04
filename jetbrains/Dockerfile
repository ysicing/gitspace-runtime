# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace JetBrains 专用镜像
# 基于 base 镜像，添加 JetBrains IDE 支持（IntelliJ/PyCharm/GoLand 等）

ARG BASE_IMAGE=ttl.sh/ysicing/gitspace-runtime:base-latest
FROM ${BASE_IMAGE}

LABEL maintainer="Gitness Team"
LABEL description="Gitspace JetBrains image with remote-dev-server support"

USER root

# 安装 JetBrains 特定依赖
RUN apt-get update && apt-get install -y \
    # 进程管理
    procps \
    # 压缩工具
    tar unzip gzip \
    # 图形库依赖
    libxext6 libxrender1 libxtst6 libxi6 libfreetype6 \
    # X11 库
    libx11-6 libxau6 libxdmcp6 libxcb1 \
    # 字体
    fontconfig fonts-dejavu \
    # 其他工具
    lsof \
    # 清理
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建 JetBrains 相关目录
RUN mkdir -p /home/vscode/.cache/JetBrains \
    /home/vscode/.config/JetBrains \
    /home/vscode/.local/share/JetBrains \
    /home/vscode/.jetbrains-ide \
    /tmp/jetbrains-download \
    && chown -R vscode:vscode /home/vscode/.cache /home/vscode/.config /home/vscode/.local /home/vscode/.jetbrains-ide /tmp/jetbrains-download

# ✅ 预装 JetBrains IDE（默认安装 IntelliJ IDEA，构建时安装避免运行时下载）
# 注意：镜像会增加约 1GB，但可以显著减少启动时间
RUN echo "Downloading and installing latest IntelliJ IDEA Ultimate..." \
    && ARCH=$(case "$(uname -m)" in arm*|aarch64) echo "linuxARM64" ;; *) echo "linux" ;; esac) \
    && DOWNLOAD_URL="https://download.jetbrains.com/idea/ideaIU-latest-${ARCH}.tar.gz" \
    && echo "Download URL: ${DOWNLOAD_URL}" \
    && curl -L --progress-bar -o /tmp/jetbrains-ide.tar.gz "${DOWNLOAD_URL}" \
    && echo "Extracting IDE..." \
    && tar -xzf /tmp/jetbrains-ide.tar.gz -C /home/vscode/.jetbrains-ide --strip-components=1 \
    && rm -f /tmp/jetbrains-ide.tar.gz \
    && chmod +x /home/vscode/.jetbrains-ide/bin/*.sh \
    && chown -R vscode:vscode /home/vscode/.jetbrains-ide \
    && echo "✓ IntelliJ IDEA pre-installed successfully" \
    && ls -lh /home/vscode/.jetbrains-ide/bin/remote-dev-server.sh

# 复制 JetBrains 专用脚本
COPY jetbrains/scripts/*.sh /usr/local/gitspace/scripts/jetbrains/
RUN chmod +x /usr/local/gitspace/scripts/jetbrains/*.sh

# 复制 JetBrains 初始化脚本
COPY jetbrains/init-jetbrains.sh /usr/local/bin/gitspace-init.sh
RUN chmod +x /usr/local/bin/gitspace-init.sh

# 设置环境变量
ENV JETBRAINS_CACHE_DIR=/home/vscode/.cache/JetBrains
ENV JETBRAINS_CONFIG_DIR=/home/vscode/.config/JetBrains
ENV JETBRAINS_DATA_DIR=/home/vscode/.local/share/JetBrains

# 切换到非 root 用户
USER vscode

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=120s --retries=3 \
    CMD [ "which", "git" ]

CMD ["sleep", "infinity"]
