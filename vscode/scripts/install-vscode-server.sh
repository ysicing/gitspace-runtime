#!/bin/bash
# 验证 VSCode Server (code-server) 是否已预装
# 注意: code-server 应该在镜像构建时预装，不在运行时安装

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

install_vscode_server() {
    # ✅ 验证镜像中预装的 code-server
    if command -v code-server > /dev/null 2>&1; then
        local installed_version
        installed_version=$(code-server --version | head -1 || echo "unknown")
        log_success "code-server pre-installed in image: $installed_version"

        # 验证可执行性
        if code-server --help > /dev/null 2>&1; then
            log_success "code-server is functional"
        else
            log_error "code-server found but not functional"
            return 1
        fi

        return 0
    fi

    # ❌ 未找到 code-server = 镜像构建失败
    log_error "=========================================="
    log_error "FATAL: code-server not found in image!"
    log_error "=========================================="
    log_error ""
    log_error "This should never happen. The image must be rebuilt with:"
    log_error "  RUN curl -fsSL https://code-server.dev/install.sh | sh"
    log_error ""
    log_error "Expected image: gitness/gitspace:vscode-latest"
    log_error "Check Dockerfile: vscode/Dockerfile"
    log_error ""
    log_error "Aborting initialization..."
    log_error "=========================================="

    return 1
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    install_vscode_server
fi
