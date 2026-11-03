#!/bin/bash
set -euo pipefail

HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-repo}"
REPO_DIR="$HOME_DIR/$REPO_NAME"
IDE_TYPE="${IDE_TYPE:-intellij}"
SSH_PORT="${SSH_PORT:-8090}"
JETBRAINS_IDE_DIR="${JETBRAINS_IDE_DIR:-$HOME_DIR/.jetbrains-ide}"
DEFAULT_IDE_PATH="${DEFAULT_IDE_PATH:-/opt/jetbrains}"
JETBRAINS_PLUGINS="${JETBRAINS_PLUGINS:-}"
COMMON_SCRIPT_DIR="/usr/local/gitspace/scripts/common"

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

resolve_ide_path() {
    if [ -f "$JETBRAINS_IDE_DIR/bin/remote-dev-server.sh" ]; then
        RESOLVED_IDE_PATH="$JETBRAINS_IDE_DIR"
    elif [ -f "$DEFAULT_IDE_PATH/bin/remote-dev-server.sh" ]; then
        RESOLVED_IDE_PATH="$DEFAULT_IDE_PATH"
    else
        log_error "remote-dev-server.sh not found in $JETBRAINS_IDE_DIR or $DEFAULT_IDE_PATH"
        return 1
    fi
    RESOLVED_IDE_PATH="$(cd "$RESOLVED_IDE_PATH" && pwd -P)"

    local gateway_dir="$HOME_DIR/.cache/JetBrains/RemoteDev/dist"
    local gateway_path="$gateway_dir/$IDE_TYPE"
    mkdir -p "$gateway_dir"
    if [ -L "$gateway_path" ]; then
        ln -sfn "$RESOLVED_IDE_PATH" "$gateway_path"
    elif [ ! -e "$gateway_path" ]; then
        ln -s "$RESOLVED_IDE_PATH" "$gateway_path"
    elif [ "$gateway_path" != "$RESOLVED_IDE_PATH" ]; then
        log_error "Gateway IDE path already exists and is not a symbolic link: $gateway_path"
        return 1
    fi
    log_info "JetBrains IDE: $RESOLVED_IDE_PATH"
}

install_jetbrains_plugins() {
    if [ -z "$JETBRAINS_PLUGINS" ]; then
        return
    fi
    local script="/usr/local/gitspace/scripts/jetbrains/setup-jetbrains-plugins.sh"
    export IDE_PATH="$RESOLVED_IDE_PATH"
    export JETBRAINS_PLUGINS
    "$script"
}

start_remote_dev_server() {
    log_info "Starting JetBrains remote-dev-server for $REPO_DIR"
    exec "$RESOLVED_IDE_PATH/bin/remote-dev-server.sh" run "$REPO_DIR" \
        --ssh-link-host 0.0.0.0 --ssh-link-port "$SSH_PORT"
}

main() {
    log_info "Starting Gitspace ${IDE_TYPE}: ${GITSPACE_IDENTIFIER:-gitspace}"
    run_as_root mkdir -p "$HOME_DIR" /var/run/sshd
    if [ "$HOME_DIR" = "/home/vscode" ] && [ ! -L "$HOME_DIR" ]; then
        run_as_root chown vscode:vscode "$HOME_DIR"
    fi

    source "$COMMON_SCRIPT_DIR/setup-git-credentials.sh"
    source "$COMMON_SCRIPT_DIR/clone-repository.sh"
    source "$COMMON_SCRIPT_DIR/run-lifecycle.sh"
    source "$COMMON_SCRIPT_DIR/setup-ssh.sh"
    source "$COMMON_SCRIPT_DIR/setup-bash-config.sh"
    setup_git_credentials
    clone_repository
    run_gitspace_lifecycle
    resolve_ide_path
    install_jetbrains_plugins
    configure_ssh_server
    run_as_root /usr/sbin/sshd -e -f "$GITSPACE_SSH_CONFIG"
    start_remote_dev_server
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main
fi
