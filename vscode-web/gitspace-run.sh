#!/bin/bash
# Gitspace VSCode Web 启动脚本
set -euo pipefail

HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-}"
REPO_DIR="$HOME_DIR/$REPO_NAME"
IDE_PORT="${IDE_PORT:-8089}"

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

# 权限提升函数
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log_error "Command requires root privileges but sudo is unavailable: $*"
        exit 1
    fi
}

# ========================================
# 主函数
# ========================================
main() {
    log_info "=========================================="
    log_info "Gitspace VSCode Web Initialization Started"
    log_info "Gitspace ID: $GITSPACE_IDENTIFIER"
    log_info "=========================================="

    # 第0步：确保 HOME 目录权限正确
    log_info "Step 0/3: Ensuring HOME directory permissions..."
    run_as_root mkdir -p "$HOME_DIR"
    run_as_root chown -R vscode:vscode "$HOME_DIR"
    log_info "HOME directory permissions set correctly"

    # 第1步：设置 Git 凭证
    log_info "Step 1/3: Setting up Git credentials..."
    source /usr/local/gitspace/scripts/common/setup-git-credentials.sh
    setup_git_credentials

    # 第2步：克隆代码仓库
    log_info "Step 2/3: Cloning repository..."
    source /usr/local/gitspace/scripts/common/clone-repository.sh
    clone_repository

    # 第3步：启动 code-server
    log_info "Step 3/3: Starting code-server..."
    start_code_server
}

# ========================================
# 启动 code-server
# ========================================
start_code_server() {
    log_info "Starting VSCode Server..."
    log_info "HOME: $HOME_DIR"
    log_info "Repository: $REPO_DIR"
    log_info "Port: $IDE_PORT"

    # 进入工作目录 (优先使用仓库目录, 否则使用 HOME)
    if [ -n "$REPO_NAME" ] && [ -d "$REPO_DIR" ]; then
        cd "$REPO_DIR"
        log_info "Working directory: $REPO_DIR"
    else
        cd "$HOME_DIR"
        log_info "Working directory: $HOME_DIR"
    fi

    # 配置目录
    config_dir="$HOME_DIR/.config/code-server"
    mkdir -p "$config_dir"

    # 创建配置文件
    cat > "$config_dir/config.yaml" <<CONFIG_EOF
bind-addr: 0.0.0.0:$IDE_PORT
auth: none
cert: false
CONFIG_EOF

    log_success "=========================================="
    log_success "Gitspace VSCode Web Initialization Completed"
    log_success "Starting code-server on port $IDE_PORT..."
    log_success "=========================================="

    # 启动 code-server（作为主进程）
    exec code-server --disable-workspace-trust "$(pwd)"
}

# 执行主函数
main
