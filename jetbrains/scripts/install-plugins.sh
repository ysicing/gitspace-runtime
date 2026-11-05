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

    if [ ! -x "$remote_dev_server" ]; then
        log_error "remote-dev-server.sh not found"
        return 1
    fi

    log_info "Installing JetBrains plugins..."
    log_info "Plugins: $plugins"

    # 插件安装日志
    local log_file="$HOME/jetbrains-plugin-install.log"

    local plugin_arguments=()
    read -r -a plugin_arguments <<< "${plugins//,/ }"
    if [ "${#plugin_arguments[@]}" -eq 0 ]; then
        return 0
    fi
    if "$remote_dev_server" installPlugins "${plugin_arguments[@]}" > "$log_file" 2>&1; then
        log_info "Plugin installation command completed"
    else
        log_error "Plugin installation command failed"
        cat "$log_file"
        return 1
    fi

    log_info "All plugins installed successfully"
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    install_jetbrains_plugins
fi
