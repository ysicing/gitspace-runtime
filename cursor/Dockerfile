# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace Cursor/Windsurf 专用镜像
# 基于 base 镜像，添加 SSH Server 支持，用于 Cursor/Windsurf Remote-SSH 连接
# - Cursor: 端口 8098
# - Windsurf: 端口 8099

FROM ghcr.io/ysicing/gitspace-runtime:base-latest

LABEL maintainer="Gitness Team"
LABEL description="Gitspace Cursor/Windsurf image with SSH server for Remote-SSH connection"

USER root

# 安装 Cursor/Windsurf 特定依赖 + OpenSSH Server
RUN apt-get update && apt-get install -y \
    # 构建工具
    build-essential \
    # Python 支持
    python3 python3-pip \
    # Node.js 和 npm 已在 base 镜像中安装
    # ✅ SSH Server（Cursor/Windsurf 核心依赖）
    openssh-server \
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
# 注意：端口由环境变量 SSH_PORT 在运行时指定（Cursor: 8098, Windsurf: 8099）
RUN echo "AllowUsers vscode" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config \
    && echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config

# 生成 SSH Host Keys
RUN ssh-keygen -A

# 复制 Cursor/Windsurf 专用脚本
COPY cursor/scripts/*.sh /usr/local/gitspace/scripts/cursor/
RUN chmod +x /usr/local/gitspace/scripts/cursor/*.sh

# 复制运行脚本
COPY cursor/gitspace-run.sh /usr/local/bin/gitspace-run.sh
RUN chmod +x /usr/local/bin/gitspace-run.sh

# 创建必要的目录并设置权限
RUN mkdir -p /home/vscode/.ssh \
    /home/vscode/.cursor-server \
    /home/vscode/.windsurf-server \
    && chown -R vscode:vscode /home/vscode/.ssh /home/vscode/.cursor-server /home/vscode/.windsurf-server \
    && chmod 700 /home/vscode/.ssh

# 设置 vscode 用户密码为空（允许无密码 SSH 登录）
# 注意：这是开发环境配置，生产环境应使用 SSH key
RUN passwd -d vscode

# 切换到 vscode 用户（SSH 会以 vscode 用户身份运行）
USER vscode

# 健康检查：检查 SSH Server 是否可用
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD [ "sh", "-c", "which sshd && which git" ]

# 默认命令：启动 SSH Server
CMD ["sleep", "infinity"]
