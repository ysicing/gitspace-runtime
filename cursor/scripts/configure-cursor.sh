#!/bin/bash
# 配置 Cursor/Windsurf IDE

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

configure_cursor() {
    local ide_type="${IDE_TYPE:-cursor}"
    local config_dir="$HOME/.config/code-server"
    local extensions="${CURSOR_EXTENSIONS:-}"

    log_info "Configuring $ide_type..."

    # 创建配置目录
    mkdir -p "$config_dir"

    # 如果有扩展需要安装
    if [ -n "$extensions" ]; then
        log_info "Installing Cursor extensions..."
        log_info "Extensions: $extensions"

        # 将逗号分隔的扩展列表转换为数组
        IFS=',' read -ra EXTENSION_ARRAY <<< "$extensions"

        local installed_count=0
        local failed_count=0

        for extension in "${EXTENSION_ARRAY[@]}"; do
            # 去除首尾空格
            extension=$(echo "$extension" | xargs)

            if [ -z "$extension" ]; then
                continue
            fi

            log_info "Installing extension: $extension"

            # 使用 code-server CLI 安装扩展
            if code-server --install-extension "$extension" > /dev/null 2>&1; then
                log_info "✓ $extension: installed successfully"
                installed_count=$((installed_count + 1))
            else
                log_error "✗ $extension: installation failed"
                failed_count=$((failed_count + 1))
            fi
        done

        log_info "Extension installation summary: $installed_count succeeded, $failed_count failed"

        if [ $failed_count -gt 0 ]; then
            log_error "Some extensions failed to install"
        fi
    else
        log_info "No extensions configured (CURSOR_EXTENSIONS not set)"
    fi

    # Cursor 特定配置（可选）
    # Cursor 基于 VSCode，大部分配置与 VSCode 相同
    # 如果需要 Cursor 特定设置，可以在这里添加

    log_info "$ide_type configuration completed"
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    configure_cursor
fi
