#!/bin/bash
# Copyright (c) 2025-2025 All rights reserved.
#
# 启动 JetBrains SSH Server + remote-dev-server 脚本
# 双进程模式：
# 1. SSH Server（后台） - 供 JetBrains Gateway 连接
# 2. remote-dev-server（前台） - JetBrains IDE 后端服务

set -e

echo "=========================================="
echo "JetBrains 双进程启动"
echo "=========================================="

# 环境变量
SSH_PORT="${SSH_PORT:-8090}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
REPO_NAME="${REPO_NAME:-repo}"
IDE_TYPE="${IDE_TYPE:-intellij}"
JETBRAINS_PLUGINS="${JETBRAINS_PLUGINS:-}"

# IDE 路径配置
# 1. 优先使用预安装的 IDE（/opt/jetbrains）
# 2. 如果提供了自定义路径，使用自定义路径
DEFAULT_IDE_PATH="${DEFAULT_IDE_PATH:-/opt/jetbrains}"
CUSTOM_IDE_PATH="${HOME}/.jetbrains-ide"

echo "配置信息:"
echo "  - SSH Port: ${SSH_PORT}"
echo "  - IDE Type: ${IDE_TYPE}"
echo "  - Workspace: ${WORKSPACE_DIR}"

# ==========================================
# 步骤 1: 启动 SSH Server（后台）
# ==========================================
echo ""
echo "=========================================="
echo "步骤 1: 启动 SSH Server"
echo "=========================================="

# 确保 SSH 运行目录存在
sudo mkdir -p /var/run/sshd

# 生成 SSH Host Keys（如果不存在）
HOST_KEYS="/etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_ed25519_key"
for KEY in $HOST_KEYS; do
    if [ ! -f "$KEY" ]; then
        echo "生成 SSH Host Key: $KEY"
        case "$KEY" in
            "/etc/ssh/ssh_host_rsa_key")
                sudo ssh-keygen -t rsa -b 4096 -f "$KEY" -N ""
                ;;
            "/etc/ssh/ssh_host_ecdsa_key")
                sudo ssh-keygen -t ecdsa -b 521 -f "$KEY" -N ""
                ;;
            "/etc/ssh/ssh_host_ed25519_key")
                sudo ssh-keygen -t ed25519 -f "$KEY" -N ""
                ;;
        esac
        sudo chmod 600 "$KEY"
        sudo chmod 644 "${KEY}.pub"
    fi
done

# 配置 SSH 端口
sudo sed -i "s/^#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
if ! grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config; then
    echo "Port ${SSH_PORT}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

echo "✓ SSH Server 配置完成"
echo "启动 sshd（后台）..."

# 启动 SSH Server（后台运行）
sudo /usr/sbin/sshd -p "${SSH_PORT}"

echo "✓ SSH Server 已启动在后台，端口: ${SSH_PORT}"

# ==========================================
# 步骤 2: 确定 IDE 路径
# ==========================================
echo ""
echo "=========================================="
echo "步骤 2: 确定 JetBrains IDE 路径"
echo "=========================================="

IDE_PATH=""

# 优先级 1: 检查是否有自定义下载的 IDE
if [ -d "$CUSTOM_IDE_PATH" ] && [ -f "$CUSTOM_IDE_PATH/bin/remote-dev-server.sh" ]; then
    IDE_PATH="$CUSTOM_IDE_PATH"
    echo "✓ 使用自定义 IDE: $IDE_PATH"
# 优先级 2: 使用预安装的 IDE
elif [ -d "$DEFAULT_IDE_PATH" ] && [ -f "$DEFAULT_IDE_PATH/bin/remote-dev-server.sh" ]; then
    IDE_PATH="$DEFAULT_IDE_PATH"
    echo "✓ 使用预安装 IDE: $IDE_PATH"
else
    echo "✗ 未找到 JetBrains IDE"
    echo "  预期路径："
    echo "    - $DEFAULT_IDE_PATH/bin/remote-dev-server.sh (预安装)"
    echo "    - $CUSTOM_IDE_PATH/bin/remote-dev-server.sh (自定义)"
    exit 1
fi

# ==========================================
# 步骤 3: 安装插件（如果配置）
# ==========================================
if [ -n "$JETBRAINS_PLUGINS" ]; then
    echo ""
    echo "=========================================="
    echo "步骤 3: 安装 JetBrains 插件"
    echo "=========================================="

    if [ -f "/usr/local/gitspace/scripts/jetbrains/setup-jetbrains-plugins.sh" ]; then
        export IDE_PATH
        export JETBRAINS_PLUGINS
        /usr/local/gitspace/scripts/jetbrains/setup-jetbrains-plugins.sh
        echo "✓ 插件安装完成"
    else
        echo "⚠ 插件安装脚本不存在，跳过"
    fi
fi

# ==========================================
# 步骤 4: 启动 JetBrains remote-dev-server（前台）
# ==========================================
echo ""
echo "=========================================="
echo "步骤 4: 启动 JetBrains remote-dev-server"
echo "=========================================="

# 查找 remote-dev-server.sh
REMOTE_DEV_SERVER="${IDE_PATH}/bin/remote-dev-server.sh"
if [ ! -f "$REMOTE_DEV_SERVER" ]; then
    echo "✗ 未找到 remote-dev-server.sh: $REMOTE_DEV_SERVER"
    exit 1
fi

# 项目路径
PROJECT_PATH="${WORKSPACE_DIR}/${REPO_NAME}"
if [ ! -d "$PROJECT_PATH" ]; then
    echo "⚠ 项目路径不存在: $PROJECT_PATH，使用 workspace"
    PROJECT_PATH="$WORKSPACE_DIR"
fi

echo "启动 remote-dev-server..."
echo "  IDE: $IDE_PATH"
echo "  Project: $PROJECT_PATH"
echo "  SSH Port: $SSH_PORT"
echo ""
echo "✓ JetBrains 环境就绪"
echo "=========================================="

# 启动 remote-dev-server（前台运行）
exec "$REMOTE_DEV_SERVER" run "$PROJECT_PATH" --ssh-link-host 0.0.0.0 --ssh-link-port "$SSH_PORT"
