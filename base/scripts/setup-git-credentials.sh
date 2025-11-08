#!/bin/bash
# 通用 Git 凭证设置脚本
set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

setup_git_credentials() {
    if [ -z "${GIT_USERNAME:-}" ] || [ -z "${GIT_PASSWORD:-}" ]; then
        log_info "No Git credentials provided, skipping credential setup"
        return 0
    fi

    log_info "Setting up Git credentials with cache (30 days timeout)"

    # 使用 git credential cache（与 Docker 实现对齐）
    # 超时时间: 2592000秒 = 30天
    # 使用 git credential cache
    git config --global credential.helper 'cache --timeout=2592000'

    # 构建带凭证的 URL
    local git_host="${GIT_HOST:-github.com}"
    local clone_url_with_creds="https://${GIT_USERNAME}:${GIT_PASSWORD}@${git_host}/"

    # 创建临时凭证文件并 approve
    cat > /tmp/.gitcontext <<EOF
url=${clone_url_with_creds}

EOF

    cat /tmp/.gitcontext | git credential approve
    rm -f /tmp/.gitcontext

    log_info "Git credentials configured successfully"

    # 设置 Git 用户信息（如果提供）
    if [ -n "${GIT_USER_NAME:-}" ]; then
        git config --global user.name "$GIT_USER_NAME"
        log_info "Git user.name set to: $GIT_USER_NAME"
    fi

    if [ -n "${GIT_USER_EMAIL:-}" ]; then
        git config --global user.email "$GIT_USER_EMAIL"
        log_info "Git user.email set to: $GIT_USER_EMAIL"
    fi
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    setup_git_credentials
fi
