#!/bin/bash
# Gitspace Cursor/Windsurf 初始化脚本
# Cursor 和 Windsurf 基于 VSCode，使用相似的安装流程

set -euo pipefail

# ========================================
# 环境变量
# ========================================
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
REPO_NAME="${REPO_NAME:-}"
REPO_DIR="$WORKSPACE_DIR/$REPO_NAME"
IDE_TYPE="${IDE_TYPE:-cursor}"
IDE_PORT="${IDE_PORT:-8089}"
GITSPACE_IDENTIFIER="${GITSPACE_IDENTIFIER:-gitspace}"

# ========================================
# 日志函数
# ========================================
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

# ========================================
# 主函数
# ========================================
main() {
    log_info "=========================================="
    log_info "Gitspace $IDE_TYPE Initialization Started"
    log_info "Gitspace ID: $GITSPACE_IDENTIFIER"
    log_info "=========================================="

    # 第1步：设置 Git 凭证
    log_info "Step 1/5: Setting up Git credentials..."
    source /usr/local/gitspace/scripts/common/setup-git-credentials.sh
    setup_git_credentials

    # 第2步：克隆代码仓库
    log_info "Step 2/5: Cloning repository..."
    source /usr/local/gitspace/scripts/common/clone-repository.sh
    clone_repository

    # 第3步：安装 code-server（Cursor/Windsurf 使用 VSCode 服务器）
    log_info "Step 3/5: Installing code-server..."
    source /usr/local/gitspace/scripts/vscode/install-vscode-server.sh
    install_vscode_server

    # 第4步：配置
    log_info "Step 4/5: Configuring $IDE_TYPE..."
    source /usr/local/gitspace/scripts/cursor/configure-cursor.sh
    configure_cursor

    # 第5步：生成启动脚本
    log_info "Step 5/5: Generating startup script..."
    generate_start_script

    log_success "=========================================="
    log_success "Gitspace $IDE_TYPE Initialization Completed"
    log_success "=========================================="
}

# ========================================
# 生成启动脚本
# ========================================
generate_start_script() {
    cat > /shared/start.sh <<'EOF'
#!/bin/bash
set -e

# 加载环境变量
export HOME=/home/vscode
export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export REPO_NAME="${REPO_NAME:-}"
export IDE_PORT="${IDE_PORT:-8089}"
export IDE_TYPE="${IDE_TYPE:-cursor}"

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

log_info "Starting $IDE_TYPE..."
log_info "Workspace: $WORKSPACE_DIR/$REPO_NAME"
log_info "Port: $IDE_PORT"

# 进入工作目录
cd "$WORKSPACE_DIR/$REPO_NAME" || cd "$HOME"

# 配置目录
config_dir="$HOME/.config/code-server"
mkdir -p "$config_dir"

# 创建配置文件
cat > "$config_dir/config.yaml" <<CONFIG_EOF
bind-addr: 0.0.0.0:$IDE_PORT
auth: none
cert: false
CONFIG_EOF

# 启动 code-server
log_info "Launching code-server for $IDE_TYPE..."
exec code-server --disable-workspace-trust "$WORKSPACE_DIR/$REPO_NAME"
EOF

    chmod +x /shared/start.sh
    log_info "Startup script created at /shared/start.sh"
}

# 执行主函数
main
