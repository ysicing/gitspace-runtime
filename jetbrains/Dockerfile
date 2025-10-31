# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace JetBrains 专用镜像
# 基于 base 镜像，添加 JetBrains IDE 支持（IntelliJ/PyCharm/GoLand 等）

FROM ghcr.io/ysicing/gitspace-runtime:base-latest

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
    /tmp/jetbrains-download \
    && chown -R vscode:vscode /home/vscode/.cache /home/vscode/.config /home/vscode/.local /tmp/jetbrains-download

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
