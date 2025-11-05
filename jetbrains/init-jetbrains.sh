#!/bin/bash
# Gitspace JetBrains 初始化脚本
# 执行顺序：Git凭证 → 克隆代码 → 下载IDE → 配置IDE → 安装插件 → 生成启动脚本

set -euo pipefail

# ========================================
# 环境变量
# ========================================
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspaces}"
REPO_NAME="${REPO_NAME:-}"
REPO_DIR="$WORKSPACE_DIR/$REPO_NAME"
IDE_TYPE="${IDE_TYPE:-intellij}"
IDE_PORT="${IDE_PORT:-8889}"
GITSPACE_IDENTIFIER="${GITSPACE_IDENTIFIER:-gitspace}"

# JetBrains 相关
JETBRAINS_IDE_DIR="$HOME/.jetbrains-ide"
TMP_DOWNLOAD_DIR="/tmp/jetbrains-download"

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
    log_info "Gitspace JetBrains Initialization Started"
    log_info "Gitspace ID: $GITSPACE_IDENTIFIER"
    log_info "IDE Type: $IDE_TYPE"
    log_info "=========================================="

    # 第1步：设置 Git 凭证
    log_info "Step 1/6: Setting up Git credentials..."
    source /usr/local/gitspace/scripts/common/setup-git-credentials.sh
    setup_git_credentials

    # 第2步：克隆代码仓库
    log_info "Step 2/6: Cloning repository..."
    source /usr/local/gitspace/scripts/common/clone-repository.sh
    clone_repository

    # 第3步：下载 JetBrains IDE
    log_info "Step 3/6: Downloading JetBrains IDE..."
    source /usr/local/gitspace/scripts/jetbrains/download-jetbrains-ide.sh
    download_jetbrains_ide

    # 第4步：配置 IDE
    log_info "Step 4/6: Configuring JetBrains IDE..."
    source /usr/local/gitspace/scripts/jetbrains/configure-jetbrains.sh
    configure_jetbrains

    # 第5步：安装插件（如果配置）
    if [ -n "${JETBRAINS_PLUGINS:-}" ]; then
        log_info "Step 5/6: Installing JetBrains plugins..."
        source /usr/local/gitspace/scripts/jetbrains/install-plugins.sh
        install_jetbrains_plugins
    else
        log_info "Step 5/6: No plugins configured, skipping..."
    fi

    # 第6步：生成启动脚本
    log_info "Step 6/6: Generating startup script..."
    generate_start_script

    log_success "=========================================="
    log_success "Gitspace JetBrains Initialization Completed"
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
export IDE_PORT="${IDE_PORT:-8889}"
export JETBRAINS_IDE_DIR="$HOME/.jetbrains-ide"

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

log_info "Starting JetBrains IDE..."
log_info "Workspace: $WORKSPACE_DIR/$REPO_NAME"
log_info "IDE Directory: $JETBRAINS_IDE_DIR"

# 检查 IDE 是否已下载
if [ ! -d "$JETBRAINS_IDE_DIR" ]; then
    log_error "JetBrains IDE not found at $JETBRAINS_IDE_DIR"
    exit 1
fi

# 查找 remote-dev-server.sh
REMOTE_DEV_SERVER="$JETBRAINS_IDE_DIR/bin/remote-dev-server.sh"

if [ ! -f "$REMOTE_DEV_SERVER" ]; then
    log_error "remote-dev-server.sh not found at $REMOTE_DEV_SERVER"
    exit 1
fi

# 启动 JetBrains IDE
log_info "Launching JetBrains remote-dev-server..."
cd "$WORKSPACE_DIR/$REPO_NAME" || cd "$HOME"

# 启动 IDE 并输出日志
exec "$REMOTE_DEV_SERVER" run "$WORKSPACE_DIR/$REPO_NAME" --ssh-link-user vscode --port "$IDE_PORT"
EOF

    chmod +x /shared/start.sh
    log_info "Startup script created at /shared/start.sh"
}

# 执行主函数
main
