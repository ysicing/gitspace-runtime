#!/bin/bash
# 通用 Git 凭证设置脚本
set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

setup_git_credentials() {
    # 设置 Git 用户信息（仅在未配置或显式提供变量时执行）
    local default_git_user_name="gitspace-user"
    local default_git_user_email="gitspace-user@gitspace.local"
    local current_git_user_name current_git_user_email
    local desired_git_user_name=""
    local desired_git_user_email=""

    current_git_user_name=$(git config --global user.name 2>/dev/null || true)
    current_git_user_email=$(git config --global user.email 2>/dev/null || true)

    if [ -n "${GIT_USER_NAME:-}" ]; then
        desired_git_user_name="$GIT_USER_NAME"
    elif [ -z "$current_git_user_name" ]; then
        desired_git_user_name="$default_git_user_name"
    fi

    if [ -n "${GIT_USER_EMAIL:-}" ]; then
        desired_git_user_email="$GIT_USER_EMAIL"
    elif [ -z "$current_git_user_email" ]; then
        desired_git_user_email="$default_git_user_email"
    fi

    if [ -n "$desired_git_user_name" ] && [ "$current_git_user_name" != "$desired_git_user_name" ]; then
        git config --global user.name "$desired_git_user_name"
        log_info "Git user.name set to: $desired_git_user_name"
    else
        log_info "Git user.name already set to: ${current_git_user_name:-<unset>}"
    fi

    if [ -n "$desired_git_user_email" ] && [ "$current_git_user_email" != "$desired_git_user_email" ]; then
        git config --global user.email "$desired_git_user_email"
        log_info "Git user.email set to: $desired_git_user_email"
    else
        log_info "Git user.email already set to: ${current_git_user_email:-<unset>}"
    fi

    # 禁用GPG签名 (Gitspace环境不需要GPG签名)
    git config --global commit.gpgsign false
    git config --global tag.gpgSign false
    log_info "Git GPG signing disabled for Gitspace environment"

    # 设置 Git 凭证（如果提供）
    if [ -z "${GIT_USERNAME:-}" ] || [ -z "${GIT_PASSWORD:-}" ]; then
        log_info "No Git credentials provided, skipping credential setup"
        return 0
    fi

    log_info "Setting up Git credentials with cache (30 days timeout)"

    # 使用 git credential cache（与 Docker 实现对齐）
    # 超时时间: 2592000秒 = 30天
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
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    setup_git_credentials
fi
