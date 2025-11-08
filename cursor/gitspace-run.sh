#!/bin/bash
# Gitspace Cursor/Windsurf 初始化脚本
# 执行顺序：Git 凭证 → 克隆仓库 → 配置 SSH → 启动 SSH
set -euo pipefail

HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-repo}"
REPO_DIR="$HOME_DIR/$REPO_NAME"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
IDE_TYPE="${IDE_TYPE:-cursor}"
SSH_PORT="${SSH_PORT:-8098}"
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

start_ssh_server() {
    log_info "Step 4/4: Starting SSH server on port ${SSH_PORT}..."
    run_as_root mkdir -p /var/run/sshd
    ensure_host_keys

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

    local ide_label="Remote-SSH"
    if [ "$IDE_TYPE" = "cursor" ]; then
        ide_label="Cursor Remote-SSH"
    elif [ "$IDE_TYPE" = "windsurf" ]; then
        ide_label="Windsurf Remote-SSH"
    fi
    log_success "  Mode: ${ide_label}"
    log_success "  Repo: ${REPO_DIR}"
    log_success "------------------------------------------"
    log_success "Sample SSH config:"
    log_success "Host gitspace-${REPO_NAME}"
    log_success "    HostName <gitspace-url>"
    log_success "    Port ${SSH_PORT}"
    log_success "    User vscode"
    log_success "    IdentityFile ~/.ssh/id_rsa"

    if [ -x "/usr/sbin/sshd" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            exec /usr/sbin/sshd -D -p "${SSH_PORT}"
        else
            exec sudo /usr/sbin/sshd -D -p "${SSH_PORT}"
        fi
    else
        log_error "/usr/sbin/sshd not found"
        exit 1
    fi
}

main() {
    log_info "=========================================="
    log_info "Gitspace Cursor/Windsurf Initialization Started"
    log_info "Gitspace ID: ${GITSPACE_IDENTIFIER}"
    log_info "IDE Type: ${IDE_TYPE}"
    log_info "Home: ${HOME_DIR}"
    log_info "Repository: ${REPO_NAME} (branch: ${BRANCH})"
    log_info "SSH Port: ${SSH_PORT}"
    log_info "=========================================="

    log_info "Step 1/4: Setting up Git credentials..."
    setup_git_credentials

    clone_repository_step
    configure_ssh_server
    start_ssh_server
}

main
