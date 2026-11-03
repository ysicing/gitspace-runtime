#!/bin/bash
set -euo pipefail

HOME_DIR="${HOME:-/home/vscode}"
REPO_NAME="${REPO_NAME:-repo}"
REPO_DIR="$HOME_DIR/$REPO_NAME"
IDE_TYPE="${IDE_TYPE:-cursor}"
if [ "$IDE_TYPE" = "windsurf" ]; then
    SSH_PORT="${SSH_PORT:-8099}"
else
    SSH_PORT="${SSH_PORT:-8098}"
fi
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
    configure_ssh_server

    log_info "Starting SSH on port $SSH_PORT for vscode, repository: $REPO_DIR"
    if [ "$(id -u)" -eq 0 ]; then
        exec /usr/sbin/sshd -D -e -f "$GITSPACE_SSH_CONFIG"
    else
        exec sudo /usr/sbin/sshd -D -e -f "$GITSPACE_SSH_CONFIG"
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main
fi
