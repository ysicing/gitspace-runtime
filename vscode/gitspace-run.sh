#!/bin/bash
# Gitspace VSCode Desktop 初始化脚本
# 执行顺序：Git 凭证 → 克隆仓库 → 配置 SSH → 启动 SSH
set -euo pipefail

HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-repo}"
REPO_DIR="$HOME_DIR/$REPO_NAME"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
IDE_TYPE="${IDE_TYPE:-vs_code}"
SSH_PORT="${SSH_PORT:-8088}"
GITSPACE_IDENTIFIER="${GITSPACE_IDENTIFIER:-gitspace}"

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
    log_info "Step 2/4: Cloning repository..."
    if [ -n "$REPO_URL" ]; then
        clone_repository
    else
        log_info "REPO_URL is empty, skipping clone step"
    fi
}

configure_ssh_server() {
    log_info "Step 3/4: Configuring SSH server..."
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
        printf '%s' "$SSH_PUBLIC_KEY" > "$HOME_DIR/.ssh/authorized_keys"
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

start_ssh_server() {
    log_info "Step 4/4: Starting SSH server on port ${SSH_PORT}..."
    run_as_root mkdir -p /var/run/sshd

    # 确保端口配置正确
    if [ -f "/etc/ssh/sshd_config" ]; then
        run_as_root sed -i "s/^#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config || true
        if ! grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config; then
            echo "Port ${SSH_PORT}" | run_as_root tee -a /etc/ssh/sshd_config >/dev/null
        fi
    fi

    log_success "SSH server ready. Connect via:"
    log_success "  Host: <gitspace-pod-ip>"
    log_success "  Port: ${SSH_PORT}"
    log_success "  User: vscode"
    log_success "  Repo: ${REPO_DIR}"

    if [ -x "/usr/sbin/sshd" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            exec /usr/sbin/sshd -D -e -p "${SSH_PORT}"
        else
            exec sudo /usr/sbin/sshd -D -e -p "${SSH_PORT}"
        fi
    else
        log_error "/usr/sbin/sshd not found"
        exit 1
    fi
}

main() {
    log_info "=========================================="
    log_info "Gitspace VSCode Desktop Initialization Started"
    log_info "Gitspace ID: ${GITSPACE_IDENTIFIER}"
    log_info "IDE Type: ${IDE_TYPE}"
    log_info "Home: ${HOME_DIR}"
    log_info "Repository: ${REPO_NAME} (branch: ${BRANCH})"
    log_info "SSH Port: ${SSH_PORT}"
    log_info "=========================================="

    # 第0步：确保 HOME 目录权限正确
    log_info "Step 0/4: Ensuring HOME directory permissions..."
    run_as_root mkdir -p "$HOME_DIR"

    # 动态获取 vscode 用户的实际 UID/GID
    local desired_uid desired_gid
    desired_uid=$(id -u vscode 2>/dev/null || echo "1000")
    desired_gid=$(id -g vscode 2>/dev/null || echo "1000")

    local current_uid current_gid
    current_uid=$(stat -c %u "$HOME_DIR" 2>/dev/null || echo "")
    current_gid=$(stat -c %g "$HOME_DIR" 2>/dev/null || echo "")

    if [ "$current_uid" != "$desired_uid" ] || [ "$current_gid" != "$desired_gid" ]; then
        if [ "$HOME_DIR" = "/home/vscode" ] && [ -d "$HOME_DIR" ]; then
            # 安全检查：确保不是符号链接
            if [ ! -L "$HOME_DIR" ]; then
                log_info "Fixing ownership of $HOME_DIR (current: ${current_uid:-unknown}:${current_gid:-unknown}, expected: $desired_uid:$desired_gid)"
                run_as_root chown -R vscode:vscode "$HOME_DIR"
                log_info "HOME directory permissions set correctly"
            else
                log_error "$HOME_DIR is a symbolic link, skipping chown for safety"
            fi
        else
            log_info "HOME_DIR is $HOME_DIR (non-standard), skipping automatic chown"
        fi
    else
        log_info "HOME directory permissions already correct ($desired_uid:$desired_gid)"
    fi

    log_info "Step 1/4: Setting up Git credentials..."
    setup_git_credentials

    clone_repository_step
    configure_ssh_server
    start_ssh_server
}

main
