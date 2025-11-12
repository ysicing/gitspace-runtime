# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace 基础镜像
# 包含所有 IDE 共享的基础工具和配置

FROM mcr.microsoft.com/devcontainers/base:ubuntu

LABEL maintainer="Gitness Team"
LABEL description="Gitspace base image with common tools"

ENV DEBIAN_FRONTEND=noninteractive

# 支持中文字符
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8
ENV TZ=Asia/Shanghai

RUN echo "export LC_ALL=C.UTF-8" >> ~/.bashrc && \
    echo "export LANG=C.UTF-8" >> ~/.bashrc && \
    echo "export LANGUAGE=C.UTF-8" >> ~/.bashrc && \
    . ~/.bashrc;

# 安装通用基础工具
RUN apt-get update && apt-get install -y \
    # 版本控制
    git git-lfs\
    # 网络工具
    curl coreutils wget ca-certificates apt-transport-https \
    # 系统工具
    sudo procps net-tools nano iputils-ping dnsutils telnet traceroute iproute2 \
    # JSON 处理
    jq \
    # envsubst
    gettext-base \
    # zsh (默认 shell)
    zsh \
    # 清理
    && git lfs install \
    && update-ca-certificates \
    && git --version \
    && git lfs --version \
    && curl --version \
    && zsh --version \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 安装 Node.js 24.x LTS（使用 NodeSource）
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && node --version \
    && npm --version \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 安装 AI CLI 工具（全局安装）
# 这些工具将在所有 IDE 镜像中可用
RUN npm install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    @google/gemini-cli \
    && claude --version || echo "Claude Code installed" \
    && codex --version || echo "Codex installed" \
    && gemini --version || echo "Gemini CLI installed"

# 创建 vscode 用户（UID/GID: 1000，与 Docker 实现对齐）
# 使用 zsh 作为默认 shell，与 root 用户保持一致
RUN if ! id -u vscode > /dev/null 2>&1; then \
        groupadd -g 1000 vscode \
        && useradd -m -u 1000 -g 1000 -s /usr/bin/zsh vscode \
        && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers; \
    fi

# 将 oh-my-zsh 安装到系统位置（不会被 PVC 覆盖）
RUN mkdir -p /opt/oh-my-zsh \
    && git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /opt/oh-my-zsh \
    && chmod -R 755 /opt/oh-my-zsh \
    && echo "✓ oh-my-zsh installed to /opt/oh-my-zsh"

# 创建 zsh 自定义目录（在 COPY 之前创建）
RUN mkdir -p /opt/zsh-custom/plugins /opt/zsh-custom/themes

# 复制 zsh 安装脚本和配置文件
COPY base/scripts/install-zsh-plugins.sh /tmp/install-zsh-plugins.sh
COPY base/zsh-config/zshrc.template /opt/zshrc.template
COPY base/zsh-theme/gaeaflow.zsh-theme /opt/zsh-custom/themes/gaeaflow.zsh-theme

# 执行 zsh 插件安装脚本并设置权限
RUN chmod +x /tmp/install-zsh-plugins.sh \
    && /tmp/install-zsh-plugins.sh \
    && rm /tmp/install-zsh-plugins.sh \
    && chmod 644 /opt/zshrc.template \
    && chmod 644 /opt/zsh-custom/themes/gaeaflow.zsh-theme \
    && echo "✓ zsh configuration completed"

# Git 全局配置
RUN git config --system core.autocrlf input \
    && git config --system init.defaultBranch main

# 创建标准目录结构
# 重要: 挂载点在 HOME 目录,与 Docker Gitspace 对齐
RUN mkdir -p /home/vscode/.config \
    /home/vscode/.local \
    /shared \
    /usr/local/gitspace/scripts/common \
    /usr/local/gitspace/scripts/vscode \
    /usr/local/gitspace/scripts/cursor \
    /usr/local/gitspace/scripts/jetbrains \
    && chown -R vscode:vscode /home/vscode /shared \
    && ln -s /home/vscode /workspaces

# 复制通用脚本 (现有的统一脚本)
COPY base/scripts/*.sh /usr/local/gitspace/scripts/common/

# 设置脚本执行权限
RUN chmod +x /usr/local/gitspace/scripts/common/*.sh

# 设置环境变量
ENV GITSPACE_SCRIPTS_DIR=/usr/local/gitspace/scripts
ENV PATH=$PATH:/usr/local/gitspace/scripts/common

# 切换到非 root 用户
USER vscode
WORKDIR /home/vscode

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD [ "which", "git" ]

# 默认保持运行
CMD ["sleep", "infinity"]
