#!/bin/bash
# 安装 JetBrains 插件

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

install_jetbrains_plugins() {
    local ide_dir="${JETBRAINS_IDE_DIR:-$HOME/.jetbrains-ide}"
    local plugins="${JETBRAINS_PLUGINS:-}"

    if [ -z "$plugins" ]; then
        log_info "No plugins configured (JETBRAINS_PLUGINS not set)"
        return 0
    fi

    # 检查 IDE 是否已安装
    if [ ! -d "$ide_dir" ]; then
        log_error "JetBrains IDE not found at $ide_dir"
        return 1
    fi

    local remote_dev_server="$ide_dir/bin/remote-dev-server.sh"

    if [ ! -f "$remote_dev_server" ]; then
        log_error "remote-dev-server.sh not found"
        return 1
    fi

    log_info "Installing JetBrains plugins..."
    log_info "Plugins: $plugins"

    # 插件安装日志
    local log_file="$HOME/jetbrains-plugin-install.log"

    # 安装插件
    if "$remote_dev_server" installPlugins $plugins > "$log_file" 2>&1; then
        log_info "Plugin installation command completed"
    else
        log_error "Plugin installation command failed"
        cat "$log_file"
        return 1
    fi

    # 解析安装结果
    local installed_count=0
    local failed_count=0

    # 将逗号分隔的插件列表转换为数组
    IFS=',' read -ra PLUGIN_ARRAY <<< "$plugins"

    for plugin in "${PLUGIN_ARRAY[@]}"; do
        # 去除首尾空格
        plugin=$(echo "$plugin" | xargs)

        if [ -z "$plugin" ]; then
            continue
        fi

        # 检查插件状态
        if grep -q "already installed: $plugin" "$log_file"; then
            log_info "✓ $plugin: already installed"
            installed_count=$((installed_count + 1))
        elif grep -q "installed plugin: PluginNode{id=$plugin" "$log_file"; then
            log_info "✓ $plugin: installed successfully"
            installed_count=$((installed_count + 1))
        else
            log_error "✗ $plugin: installation failed"
            failed_count=$((failed_count + 1))
        fi
    done

    log_info "Plugin installation summary: $installed_count succeeded, $failed_count failed"

    if [ $failed_count -gt 0 ]; then
        log_error "Some plugins failed to install. Check log: $log_file"
        return 1
    fi

    log_info "All plugins installed successfully"
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    install_jetbrains_plugins
fi
