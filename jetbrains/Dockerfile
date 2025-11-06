# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace JetBrains 专用镜像
# 基于 base 镜像，添加 SSH Server + JetBrains IDE 支持
#
# 支持的 IDE 产品代码：
# - IIC: IntelliJ IDEA Community (默认)
# - GO: GoLand
# - PCC: PyCharm Community
# - WS: WebStorm
# - CL: CLion
# - PS: PHPStorm
# - RM: RubyMine
# - RD: Rider
#
# 使用方法：
# docker build --build-arg IDE_PRODUCT_CODE=GO --build-arg IDE_NAME=goland -t goland:latest .

FROM ghcr.io/ysicing/gitspace-runtime:base-latest

LABEL maintainer="Gitness Team"
LABEL description="Gitspace JetBrains image with SSH server and remote-dev-server support"

# IDE 产品配置
# IDE_PRODUCT_CODE: JetBrains 产品代码（用于下载）
# IDE_NAME: IDE 名称（用于标识）
ARG IDE_PRODUCT_CODE=IIC
ARG IDE_NAME=intellij

USER root

# 安装 JetBrains 特定依赖 + OpenSSH Server
RUN apt-get update && apt-get install -y \
    # ✅ SSH Server（JetBrains 需要 SSH 连接）
    openssh-server \
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
    lsof curl \
    # 清理
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建 SSH 运行目录
RUN mkdir -p /var/run/sshd /etc/ssh

# 配置 SSH Server
# - AllowUsers: 只允许 vscode 用户连接
# - PasswordAuthentication: 支持密码认证（开发环境）
# - PubkeyAuthentication: 支持 SSH key 认证（推荐）
# - PermitEmptyPasswords: 允许空密码（简化开发）
# 注意：端口由环境变量 SSH_PORT 在运行时指定（不同 IDE 使用不同端口）
RUN echo "AllowUsers vscode" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config \
    && echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config

# 生成 SSH Host Keys
RUN ssh-keygen -A

# 预安装 JetBrains IDE（根据 IDE_PRODUCT_CODE 下载对应产品）
# 参考 JetBrains 官方下载 API
RUN mkdir -p /opt/jetbrains /tmp/jetbrains-download && \
    # 下载指定产品的最新版本
    echo "Downloading JetBrains IDE: ${IDE_NAME} (code: ${IDE_PRODUCT_CODE})" && \
    curl -fsSL "https://download.jetbrains.com/product?code=${IDE_PRODUCT_CODE}&latest&distribution=linux" \
    -o /tmp/jetbrains-download/ide.tar.gz && \
    # 解压到 /opt/jetbrains
    tar -xzf /tmp/jetbrains-download/ide.tar.gz -C /opt/jetbrains --strip-components=1 && \
    # 清理下载文件
    rm -rf /tmp/jetbrains-download && \
    # 设置权限
    chown -R vscode:vscode /opt/jetbrains

# 创建 JetBrains 相关目录
RUN mkdir -p /home/vscode/.cache/JetBrains \
    /home/vscode/.config/JetBrains \
    /home/vscode/.local/share/JetBrains \
    /home/vscode/.jetbrains-ide \
    /home/vscode/.ssh \
    && chown -R vscode:vscode /home/vscode/.cache /home/vscode/.config /home/vscode/.local /home/vscode/.jetbrains-ide /home/vscode/.ssh \
    && chmod 700 /home/vscode/.ssh

# 设置 IDE 路径环境变量
ENV JETBRAINS_IDE_DIR=/opt/jetbrains
ENV DEFAULT_IDE_PATH=/opt/jetbrains
ENV IDE_NAME=${IDE_NAME}

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

# 切换到 vscode 用户
USER vscode

# 健康检查：检查 SSH Server 是否可用
HEALTHCHECK --interval=30s --timeout=3s --start-period=120s --retries=3 \
    CMD [ "sh", "-c", "which sshd && which git" ]

CMD ["sleep", "infinity"]
