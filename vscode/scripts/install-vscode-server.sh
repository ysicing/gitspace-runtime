#!/bin/bash
# 安装 VSCode Server (code-server)

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

install_vscode_server() {
    # 检查是否已安装
    if command -v code-server > /dev/null 2>&1; then
        local installed_version
        installed_version=$(code-server --version | head -1 || echo "unknown")
        log_info "code-server already installed: $installed_version"
        return 0
    fi

    log_info "code-server not found, installing..."

    # 使用官方安装脚本（与 Docker 实现对齐）
    if curl -fsSL https://code-server.dev/install.sh | sh; then
        log_info "code-server installed successfully"

        # 验证安装
        if command -v code-server > /dev/null 2>&1; then
            local version
            version=$(code-server --version | head -1 || echo "unknown")
            log_info "Installed version: $version"
        else
            log_error "code-server installation verification failed"
            return 1
        fi
    else
        log_error "Failed to install code-server"
        return 1
    fi
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    install_vscode_server
fi
