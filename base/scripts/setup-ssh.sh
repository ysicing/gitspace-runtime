#!/bin/bash
set -euo pipefail

configure_ssh_server() {
    local config_path="${1:-/run/gitspace/sshd_config}"
    local access_type="${GITSPACE_ACCESS_TYPE:-user_credentials}"
    local password_auth="no"
    local public_key_auth="no"
    local host_key_dir="$HOME_DIR/.gitspace/ssh-host-keys"

    case "$access_type" in
        user_credentials) password_auth="yes" ;;
        ssh_key) public_key_auth="yes" ;;
        combined) password_auth="yes"; public_key_auth="yes" ;;
        *) log_error "Unsupported GITSPACE_ACCESS_TYPE: $access_type"; return 1 ;;
    esac

    if [ "$password_auth" = "yes" ] && [ -z "${GITSPACE_ACCESS_KEY:-}" ]; then
        log_error "GITSPACE_ACCESS_KEY is required for password authentication"
        return 1
    fi
    if [ "$public_key_auth" = "yes" ] && [ -z "${SSH_PUBLIC_KEY:-}" ]; then
        log_error "SSH_PUBLIC_KEY is required for public key authentication"
        return 1
    fi

    chmod go-w "$HOME_DIR"
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    printf '%s\n' "${SSH_PUBLIC_KEY:-}" > "$HOME_DIR/.ssh/authorized_keys"
    if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
        : > "$HOME_DIR/.ssh/authorized_keys"
    fi
    chmod 600 "$HOME_DIR/.ssh/authorized_keys"

    if [ "$password_auth" = "yes" ]; then
        printf 'vscode:%s\n' "$GITSPACE_ACCESS_KEY" | run_as_root chpasswd
    fi

    # Host Key 随开发环境持久化，不使用镜像中可能共享的服务器私钥。
    if [ -L "$HOME_DIR/.gitspace" ] || [ -L "$host_key_dir" ]; then
        log_error "SSH host key directory must not be a symbolic link"
        return 1
    fi
    run_as_root mkdir -p "$host_key_dir" "$(dirname "$config_path")"
    run_as_root chown 0:0 "$host_key_dir"
    run_as_root chmod 700 "$host_key_dir"
    if ! run_as_root test -f "$host_key_dir/ssh_host_ed25519_key"; then
        run_as_root ssh-keygen -q -t ed25519 -f "$host_key_dir/ssh_host_ed25519_key" -N ""
    fi
    run_as_root chmod 600 "$host_key_dir/ssh_host_ed25519_key"
    run_as_root tee "$config_path" >/dev/null <<CONFIG_EOF
Port ${SSH_PORT}
HostKey ${host_key_dir}/ssh_host_ed25519_key
PidFile $(dirname "$config_path")/sshd.pid
AllowUsers vscode
PermitRootLogin no
PasswordAuthentication ${password_auth}
KbdInteractiveAuthentication no
PubkeyAuthentication ${public_key_auth}
PermitEmptyPasswords no
UsePAM yes
AuthorizedKeysFile ${HOME_DIR}/.ssh/authorized_keys
Subsystem sftp internal-sftp
CONFIG_EOF
    run_as_root chmod 600 "$config_path"
    run_as_root /usr/sbin/sshd -t -f "$config_path"
    export GITSPACE_SSH_CONFIG="$config_path"
    log_info "SSH authentication configured: $access_type"
}
