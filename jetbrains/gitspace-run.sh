#!/bin/bash
# Gitspace JetBrains 初始化脚本
# 执行顺序：Git 凭证 → 克隆仓库 → 配置 SSH → 启动 SSH → 解析 IDE → 安装插件 → 启动 remote-dev
set -euo pipefail

HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-repo}"
REPO_DIR="$HOME_DIR/$REPO_NAME"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
IDE_TYPE="${IDE_TYPE:-intellij}"
SSH_PORT="${SSH_PORT:-8090}"
GITSPACE_IDENTIFIER="${GITSPACE_IDENTIFIER:-gitspace}"

JETBRAINS_IDE_DIR="${JETBRAINS_IDE_DIR:-$HOME_DIR/.jetbrains-ide}"
DEFAULT_IDE_PATH="${DEFAULT_IDE_PATH:-/opt/jetbrains}"
JETBRAINS_PLUGINS="${JETBRAINS_PLUGINS:-}"
IDE_DOWNLOAD_URL_AMD64="${IDE_DOWNLOAD_URL_AMD64:-}"
IDE_DOWNLOAD_URL_ARM64="${IDE_DOWNLOAD_URL_ARM64:-}"
IDE_DIR_NAME="${IDE_DIR_NAME:-}"

COMMON_SCRIPT_DIR="/usr/local/gitspace/scripts/common"
SETUP_SCRIPT="$COMMON_SCRIPT_DIR/setup-git-credentials.sh"
CLONE_SCRIPT="$COMMON_SCRIPT_DIR/clone-repository.sh"

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

if [ -f "$SETUP_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$SETUP_SCRIPT"
else
    echo "[ERROR] Missing script: $SETUP_SCRIPT" >&2
    exit 1
fi

if [ -f "$CLONE_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$CLONE_SCRIPT"
else
    echo "[ERROR] Missing script: $CLONE_SCRIPT" >&2
    exit 1
fi

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

clone_repository_step() {
    log_info "Step 2/7: Cloning repository..."
    if [ -n "$REPO_URL" ]; then
        clone_repository
    else
        log_info "REPO_URL is empty, skipping clone step"
    fi
}

configure_ssh_server() {
    log_info "Step 3/7: Configuring SSH server..."
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"

    # 设置用户密码（使用 GITSPACE_ACCESS_KEY 或空密码）
    if [ -n "${GITSPACE_ACCESS_KEY:-}" ]; then
        log_info "Setting SSH password from GITSPACE_ACCESS_KEY"
        echo "vscode:${GITSPACE_ACCESS_KEY}" | run_as_root chpasswd
    else
        log_info "No GITSPACE_ACCESS_KEY provided, using empty password"
        # vscode 用户已在 Dockerfile 中设置为空密码
    fi

    if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
        printf '%s\n' "$SSH_PUBLIC_KEY" > "$HOME_DIR/.ssh/authorized_keys"
        chmod 600 "$HOME_DIR/.ssh/authorized_keys"
        log_info "SSH public key configured"
    else
        log_info "No SSH public key provided; password authentication will be used"
    fi

    if [ -f "/etc/ssh/sshd_config" ]; then
        run_as_root sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
        run_as_root sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true
        run_as_root sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config || true
        log_info "sshd_config updated successfully"
    else
        log_error "/etc/ssh/sshd_config not found"
    fi
}

ensure_host_keys() {
    local keys=(
        "/etc/ssh/ssh_host_rsa_key:rsa:4096"
        "/etc/ssh/ssh_host_ecdsa_key:ecdsa:521"
        "/etc/ssh/ssh_host_ed25519_key:ed25519:0"
    )

    for entry in "${keys[@]}"; do
        IFS=":" read -r key_path key_type key_bits <<<"$entry"
        if [ ! -f "$key_path" ]; then
            log_info "Generating SSH host key: $key_path"
            case "$key_type" in
                rsa)
                    run_as_root ssh-keygen -t rsa -b "$key_bits" -f "$key_path" -N ""
                    ;;
                ecdsa)
                    run_as_root ssh-keygen -t ecdsa -b "$key_bits" -f "$key_path" -N ""
                    ;;
                ed25519)
                    run_as_root ssh-keygen -t ed25519 -f "$key_path" -N ""
                    ;;
            esac
            run_as_root chmod 600 "$key_path"
            run_as_root chmod 644 "${key_path}.pub"
        fi
    done
}

start_ssh_server_background() {
    log_info "Step 4/7: Starting SSH server in background on port ${SSH_PORT}..."
    run_as_root mkdir -p /var/run/sshd
    ensure_host_keys

    if [ -f "/etc/ssh/sshd_config" ]; then
        run_as_root sed -i "s/^#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config || true
        if ! grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config; then
            echo "Port ${SSH_PORT}" | run_as_root tee -a /etc/ssh/sshd_config >/dev/null
        fi
    fi

    if [ -x "/usr/sbin/sshd" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            /usr/sbin/sshd -p "${SSH_PORT}"
        else
            sudo /usr/sbin/sshd -p "${SSH_PORT}"
        fi
        log_info "SSH server listening on port ${SSH_PORT}"
    else
        log_error "/usr/sbin/sshd not found"
        exit 1
    fi
}

resolve_ide_path() {
    log_info "Step 5/7: Resolving JetBrains IDE path..."
    RESOLVED_IDE_PATH=""

    if [ -d "$JETBRAINS_IDE_DIR" ] && [ -f "$JETBRAINS_IDE_DIR/bin/remote-dev-server.sh" ]; then
        RESOLVED_IDE_PATH="$JETBRAINS_IDE_DIR"
        log_info "Using custom IDE: $RESOLVED_IDE_PATH"
    elif [ -d "$DEFAULT_IDE_PATH" ] && [ -f "$DEFAULT_IDE_PATH/bin/remote-dev-server.sh" ]; then
        RESOLVED_IDE_PATH="$DEFAULT_IDE_PATH"
        log_info "Using preinstalled IDE: $RESOLVED_IDE_PATH"
    else
        log_error "Unable to locate remote-dev-server.sh. Checked:"
        log_error "  - $JETBRAINS_IDE_DIR/bin/remote-dev-server.sh"
        log_error "  - $DEFAULT_IDE_PATH/bin/remote-dev-server.sh"
        exit 1
    fi
}

install_jetbrains_plugins() {
    log_info "Step 6/7: Installing JetBrains plugins..."
    if [ -z "$JETBRAINS_PLUGINS" ]; then
        log_info "JETBRAINS_PLUGINS is empty, skipping plugin installation"
        return
    fi

    local script="/usr/local/gitspace/scripts/jetbrains/setup-jetbrains-plugins.sh"
    if [ -f "$script" ]; then
        export IDE_PATH="$RESOLVED_IDE_PATH"
        export JETBRAINS_PLUGINS
        "$script"
        log_info "JetBrains plugins installed: $JETBRAINS_PLUGINS"
    else
        log_error "Plugin installer not found at $script, skipping"
    fi
}

start_remote_dev_server() {
    log_info "Step 7/7: Starting JetBrains remote-dev-server..."
    local remote_dev="${RESOLVED_IDE_PATH}/bin/remote-dev-server.sh"
    if [ ! -f "$remote_dev" ]; then
        log_error "remote-dev-server.sh not found at $remote_dev"
        exit 1
    fi

    local project_path="$REPO_DIR"
    if [ ! -d "$project_path" ]; then
        log_info "Repository path not found: $project_path. Using HOME instead."
        project_path="$HOME_DIR"
    fi

    log_success "JetBrains Gateway connection details:"
    log_success "  SSH Host: <gitspace-pod-ip>"
    log_success "  SSH Port: ${SSH_PORT}"
    log_success "  SSH User: vscode"
    log_success "  Project Path: ${project_path}"
    log_success "=========================================="

    exec "$remote_dev" run "$project_path" --ssh-link-host 0.0.0.0 --ssh-link-port "$SSH_PORT"
}

main() {
    log_info "=========================================="
    log_info "Gitspace JetBrains Initialization Started"
    log_info "Gitspace ID: ${GITSPACE_IDENTIFIER}"
    log_info "IDE Type: ${IDE_TYPE}"
    log_info "Home: ${HOME_DIR}"
    log_info "Repository: ${REPO_NAME} (branch: ${BRANCH})"
    log_info "SSH Port: ${SSH_PORT}"
    log_info "=========================================="

    # 第0步：确保 HOME 目录权限正确
    log_info "Step 0/7: Ensuring HOME directory permissions..."
    run_as_root mkdir -p "$HOME_DIR"
    run_as_root chown -R vscode:vscode "$HOME_DIR"
    log_info "HOME directory permissions set correctly"

    log_info "Step 1/7: Setting up Git credentials..."
    setup_git_credentials

    clone_repository_step
    configure_ssh_server
    start_ssh_server_background
    resolve_ide_path
    install_jetbrains_plugins
    start_remote_dev_server
}

main
