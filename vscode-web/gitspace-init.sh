#!/bin/bash
# VSCode 预构建配置迁移脚本
set -euo pipefail

PREBUILT_DIR="/opt/gitspace-vscode"
TARGET_DIR="/home/vscode"
VSCODE_USER="vscode"
MARKER_FILE="$TARGET_DIR/.gitspace-migrated"

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

# 幂等性检查
if [ -f "$MARKER_FILE" ]; then
    echo "Migrate: skipped (already migrated)"
    exit 0
fi

# 检查预构建配置
if [ ! -d "$PREBUILT_DIR/.config/code-server" ] && [ ! -d "$PREBUILT_DIR/.local/share/code-server" ]; then
    echo "Migrate: no pre-built config found"
    exit 0
fi

echo "Migrate: starting"

# 确保 /home/vscode 目录存在且权限正确
run_as_root mkdir -p "$TARGET_DIR"
run_as_root chown $VSCODE_USER:$VSCODE_USER "$TARGET_DIR"

# 创建目标目录
run_as_root mkdir -p "$TARGET_DIR/.config"
run_as_root mkdir -p "$TARGET_DIR/.local/share"
run_as_root chown -R $VSCODE_USER:$VSCODE_USER "$TARGET_DIR/.config" "$TARGET_DIR/.local"

# 迁移 .config
if [ -d "$PREBUILT_DIR/.config/code-server" ]; then
    if [ ! -d "$TARGET_DIR/.config/code-server" ] || [ -z "$(ls -A $TARGET_DIR/.config/code-server 2>/dev/null)" ]; then
        run_as_root cp -r "$PREBUILT_DIR/.config/code-server" "$TARGET_DIR/.config/"
        run_as_root chown -R $VSCODE_USER:$VSCODE_USER "$TARGET_DIR/.config/code-server"
        echo "Migrate: config migrated"
    else
        echo "Migrate: config exists, skipped"
    fi
fi

# 迁移 .local/share
if [ -d "$PREBUILT_DIR/.local/share/code-server" ]; then
    if [ ! -d "$TARGET_DIR/.local/share/code-server" ] || [ -z "$(ls -A $TARGET_DIR/.local/share/code-server 2>/dev/null)" ]; then
        run_as_root cp -r "$PREBUILT_DIR/.local/share/code-server" "$TARGET_DIR/.local/share/"
        run_as_root chown -R $VSCODE_USER:$VSCODE_USER "$TARGET_DIR/.local/share/code-server"
        echo "Migrate: extensions migrated"
    else
        echo "Migrate: extensions exist, skipped"
    fi
fi

# 创建标记
echo "done" > "$MARKER_FILE"
run_as_root chown $VSCODE_USER:$VSCODE_USER "$MARKER_FILE"
echo "Migrate: completed"
