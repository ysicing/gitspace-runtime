#!/bin/bash
# Gitspace zsh 配置初始化脚本
# 用于在容器启动时为 vscode 用户设置 zsh 配置
set -euo pipefail

ZSHRC_TEMPLATE="/opt/zshrc.template"
HOME_DIR="${HOME:-/home/vscode}"
ZSHRC_FILE="$HOME_DIR/.zshrc"
MARKER_FILE="$HOME_DIR/.zsh-initialized"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# 检查是否已初始化（幂等性）
if [ -f "$MARKER_FILE" ]; then
    log_info "zsh config already initialized, skipping"
    return 0 2>/dev/null || exit 0
fi

log_info "Initializing zsh configuration..."

# 检查 zsh 是否安装
if ! command -v zsh >/dev/null 2>&1; then
    log_info "zsh not found, skipping zsh configuration"
    return 0 2>/dev/null || exit 0
fi

# 检查模板文件是否存在
if [ ! -f "$ZSHRC_TEMPLATE" ]; then
    log_info "zsh template not found at $ZSHRC_TEMPLATE, skipping"
    return 0 2>/dev/null || exit 0
fi

# 检查 oh-my-zsh 是否存在
if [ ! -d "/opt/oh-my-zsh" ]; then
    log_info "oh-my-zsh not found at /opt/oh-my-zsh, skipping"
    return 0 2>/dev/null || exit 0
fi

# 如果用户还没有 .zshrc，则从模板创建
if [ ! -f "$ZSHRC_FILE" ]; then
    log_info "Creating .zshrc from template"
    cp "$ZSHRC_TEMPLATE" "$ZSHRC_FILE"
    chmod 644 "$ZSHRC_FILE"
    log_info ".zshrc created successfully"
else
    log_info ".zshrc already exists, keeping user's configuration"
fi

# 创建标记文件
touch "$MARKER_FILE"
log_info "zsh configuration initialized"
