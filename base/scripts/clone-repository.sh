#!/bin/bash
# 通用代码克隆脚本

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

clone_repository() {
    local repo_url="${REPO_URL:-}"
    local branch="${BRANCH:-main}"
    local repo_name="${REPO_NAME:-}"

    # 对齐 Docker Gitspace: 优先使用 HOME 目录
    local workspace_dir="${HOME:-/home/vscode}"

    # 向后兼容: 如果设置了 WORKSPACE_DIR, 使用它 (但打印警告)
    if [ -n "${WORKSPACE_DIR:-}" ]; then
        if [ "$WORKSPACE_DIR" != "$workspace_dir" ]; then
            log_info "⚠️  Using WORKSPACE_DIR=$WORKSPACE_DIR (deprecated, recommend using HOME)"
        fi
        workspace_dir="$WORKSPACE_DIR"
    fi

    local repo_dir="$workspace_dir/$repo_name"

    if [ -z "$repo_url" ] || [ -z "$repo_name" ]; then
        log_error "REPO_URL and REPO_NAME are required"
        return 1
    fi

    log_info "=========================================="
    log_info "Cloning repository: $repo_url"
    log_info "Branch: $branch"
    log_info "Target directory: $repo_dir"
    log_info "HOME: $HOME"
    log_info "=========================================="

    # 确保 workspace 目录存在且有正确的权限
    if [ ! -d "$workspace_dir" ]; then
        log_info "Creating workspace directory: $workspace_dir"
        sudo mkdir -p "$workspace_dir" || mkdir -p "$workspace_dir"
    fi

    # 修复权限（使用当前用户）
    current_user=$(id -u)
    current_group=$(id -g)
    workspace_owner=$(stat -c '%u' "$workspace_dir" 2>/dev/null || stat -f '%u' "$workspace_dir" 2>/dev/null || echo "0")

    if [ "$workspace_owner" != "$current_user" ]; then
        log_info "Fixing workspace permissions (current owner: $workspace_owner, expected: $current_user)"
        sudo chown -R "$current_user:$current_group" "$workspace_dir" 2>/dev/null || true
    fi

    # 打印最新 commit SHA（与 Docker 实现对齐）
    log_info "Fetching latest commit SHA from remote..."
    local latest_commit
    latest_commit=$(git ls-remote "$repo_url" "$branch" 2>/dev/null | awk '{print $1}' || true)

    if [ -n "$latest_commit" ]; then
        log_info "Latest commit SHA: $latest_commit"
    else
        log_info "Could not fetch latest commit SHA (public repo might not require auth)"
    fi

    # 克隆仓库（如果不存在）
    if [ ! -d "$repo_dir/.git" ]; then
        log_info "Cloning repository..."

        # 重试机制（最多3次）
        local max_retries=3
        local retry_count=0
        local retry_delay=5

        while [ $retry_count -lt $max_retries ]; do
            if git clone "$repo_url" --branch "$branch" "$repo_dir" 2>&1; then
                log_info "Repository cloned successfully"
                break
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log_info "Clone failed, retrying in ${retry_delay}s... (attempt $((retry_count + 1))/$max_retries)"
                    sleep $retry_delay
                    retry_delay=$((retry_delay * 2))  # 指数退避
                else
                    log_error "Failed to clone repository after $max_retries attempts"
                    return 1
                fi
            fi
        done
    else
        log_info "Repository already exists at $repo_dir, skipping clone"
    fi

    # 进入仓库目录
    cd "$repo_dir" || return 1

    # 打印 top 10 commits（与 Docker 实现对齐）
    log_info "Recent commits:"
    git log -n 10 --pretty=format:"%h %s" 2>/dev/null | while IFS= read -r commit; do
        log_info "  $commit"
    done || log_info "Could not fetch commit history"

    # 配置 safe.directory
    git config --global --add safe.directory "$repo_dir"
    log_info "Added $repo_dir to Git safe.directory"

    # 创建 devcontainer.json（如果不存在，与 Docker 实现对齐）
    local devcontainer_dir="$repo_dir/.devcontainer"
    local devcontainer_file="$devcontainer_dir/devcontainer.json"

    if [ ! -f "$devcontainer_file" ]; then
        log_info "Creating .devcontainer/devcontainer.json..."
        mkdir -p "$devcontainer_dir"

        local default_image="${DEFAULT_IMAGE:-mcr.microsoft.com/devcontainers/base:ubuntu}"

        cat > "$devcontainer_file" <<EOF
{
    "image": "$default_image"
}
EOF
        log_info "devcontainer.json created"
    else
        log_info ".devcontainer/devcontainer.json already exists"
    fi

    log_info "=========================================="
    log_info "Repository setup completed"
    log_info "=========================================="
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    clone_repository
fi
