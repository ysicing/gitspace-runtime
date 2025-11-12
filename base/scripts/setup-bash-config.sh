#!/bin/bash
# Gitspace bash 配置初始化脚本
# 用于在容器启动时为 vscode 用户设置 bash 配置
set -euo pipefail

BASHRC_TEMPLATE="/opt/bashrc.template"
BASH_PROFILE_TEMPLATE="/opt/bash_profile.template"
HOME_DIR="${HOME:-/home/vscode}"
BASHRC_FILE="$HOME_DIR/.bashrc"
BASH_PROFILE_FILE="$HOME_DIR/.bash_profile"
MARKER_FILE="$HOME_DIR/.bash-initialized"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# 权限提升函数
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log_info "Command requires root privileges but sudo is unavailable: $*"
        return 1
    fi
}

# 检查是否已初始化（幂等性）
if [ -f "$MARKER_FILE" ]; then
    log_info "bash config already initialized, skipping"
    return 0 2>/dev/null || exit 0
fi

log_info "Initializing bash configuration..."

# 检查模板文件是否存在
if [ ! -f "$BASHRC_TEMPLATE" ]; then
    log_info "bash template not found at $BASHRC_TEMPLATE, skipping"
    return 0 2>/dev/null || exit 0
fi

# 确保 HOME 目录存在且权限正确
run_as_root mkdir -p "$HOME_DIR"

# 如果用户还没有 .bashrc，则从模板创建
if [ ! -f "$BASHRC_FILE" ]; then
    log_info "Creating .bashrc from template"

    # 使用 root 权限复制文件，然后设置正确的所有者
    run_as_root cp "$BASHRC_TEMPLATE" "$BASHRC_FILE"
    run_as_root chown vscode:vscode "$BASHRC_FILE"
    run_as_root chmod 644 "$BASHRC_FILE"

    log_info ".bashrc created successfully"
else
    log_info ".bashrc already exists, appending custom PS1 if not present"

    # 检查是否已经有自定义 PS1
    if ! grep -q "# Gitspace Custom PS1" "$BASHRC_FILE"; then
        # 从模板提取自定义 PS1 部分并追加
        if grep -A 50 "# Gitspace Custom PS1" "$BASHRC_TEMPLATE" >> "$BASHRC_FILE"; then
            run_as_root chown vscode:vscode "$BASHRC_FILE"
            log_info "Custom PS1 appended to existing .bashrc"
        fi
    else
        log_info "Custom PS1 already exists in .bashrc"
    fi
fi

# 设置 .bash_profile 以确保 SSH 登录时加载 .bashrc
if [ ! -f "$BASH_PROFILE_FILE" ]; then
    if [ -f "$BASH_PROFILE_TEMPLATE" ]; then
        log_info "Creating .bash_profile from template"
        run_as_root cp "$BASH_PROFILE_TEMPLATE" "$BASH_PROFILE_FILE"
        run_as_root chown vscode:vscode "$BASH_PROFILE_FILE"
        run_as_root chmod 644 "$BASH_PROFILE_FILE"
        log_info ".bash_profile created successfully"
    else
        # 如果模板不存在，直接创建简单的 .bash_profile
        log_info "Creating .bash_profile (template not found, using inline content)"
        cat > "$BASH_PROFILE_FILE" <<'EOF'
# ~/.bash_profile: executed by bash(1) for login shells.

# Source .bashrc if it exists
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
        run_as_root chown vscode:vscode "$BASH_PROFILE_FILE"
        run_as_root chmod 644 "$BASH_PROFILE_FILE"
        log_info ".bash_profile created successfully (inline)"
    fi
else
    log_info ".bash_profile already exists, checking if it sources .bashrc"

    # 检查是否已经 source .bashrc
    if ! grep -q "\.bashrc" "$BASH_PROFILE_FILE"; then
        log_info "Adding .bashrc source to existing .bash_profile"
        cat >> "$BASH_PROFILE_FILE" <<'EOF'

# Source .bashrc for Gitspace
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
        run_as_root chown vscode:vscode "$BASH_PROFILE_FILE"
        log_info ".bashrc source added to .bash_profile"
    else
        log_info ".bash_profile already sources .bashrc"
    fi
fi

# 创建标记文件
run_as_root touch "$MARKER_FILE"
run_as_root chown vscode:vscode "$MARKER_FILE"
log_info "bash configuration initialized (login and non-login shells supported)"
