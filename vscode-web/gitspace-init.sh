#!/bin/bash
# VSCode 预构建配置迁移脚本
set -euo pipefail

PREBUILT_DIR="${1:-/opt/gitspace-vscode}"
TARGET_DIR="${HOME:-/home/vscode}"
VSCODE_USER="vscode"

# 权限提升函数
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "[ERROR] Command requires root privileges but sudo is unavailable: $*" >&2
        exit 1
    fi
}

# 检查预构建配置
if [ ! -d "$PREBUILT_DIR/.config/code-server" ] && [ ! -d "$PREBUILT_DIR/.local/share/code-server" ]; then
    echo "Migrate: no pre-built config found"
    exit 0
fi

echo "Migrate: starting"

if [ -L "$TARGET_DIR" ]; then
    echo "[ERROR] HOME must not be a symbolic link" >&2
    exit 1
fi

# 确保 /home/vscode 目录存在且权限正确
run_as_root mkdir -p "$TARGET_DIR"
if [ "$TARGET_DIR" = "/home/vscode" ]; then
    run_as_root chown "$VSCODE_USER:$VSCODE_USER" "$TARGET_DIR"
fi

python3 "${GITSPACE_SCRIPTS_DIR:-/usr/local/gitspace/scripts}/vscode/seed-prebuilt.py" \
    "$PREBUILT_DIR" "$TARGET_DIR"
echo "Migrate: completed"
