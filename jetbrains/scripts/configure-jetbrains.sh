#!/bin/bash
# 配置 JetBrains IDE

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

configure_jetbrains() {
    local ide_dir="${JETBRAINS_IDE_DIR:-$HOME/.jetbrains-ide}"
    local config_dir="${JETBRAINS_CONFIG_DIR:-$HOME/.config/JetBrains}"
    local cache_dir="${JETBRAINS_CACHE_DIR:-$HOME/.cache/JetBrains}"

    # 检查 IDE 是否已安装
    if [ ! -d "$ide_dir" ]; then
        log_error "JetBrains IDE not found at $ide_dir"
        return 1
    fi

    log_info "Configuring JetBrains IDE..."

    # 创建配置目录
    mkdir -p "$config_dir" "$cache_dir"

    # 设置 JVM 选项（可选，通过环境变量配置）
    if [ -n "${JETBRAINS_JVM_OPTIONS:-}" ]; then
        local vmoptions_file="$ide_dir/bin/idea64.vmoptions"

        if [ -f "$vmoptions_file" ]; then
            log_info "Configuring JVM options..."
            echo "$JETBRAINS_JVM_OPTIONS" >> "$vmoptions_file"
        fi
    fi

    # 设置系统属性（可选）
    if [ -n "${JETBRAINS_PROPERTIES:-}" ]; then
        local properties_file="$ide_dir/bin/idea.properties"

        if [ -f "$properties_file" ]; then
            log_info "Configuring IDE properties..."
            echo "$JETBRAINS_PROPERTIES" >> "$properties_file"
        fi
    fi

    log_info "JetBrains IDE configuration completed"
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    configure_jetbrains
fi
