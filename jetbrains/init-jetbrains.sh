#!/bin/bash
# Copyright (c) 2025-2025 All rights reserved.
#
# Gitspace JetBrains 初始化并启动脚本
# 负责：
# 1. 配置 Git 凭证
# 2. 克隆代码仓库
# 3. 配置 SSH Server
# 4. 启动 SSH Server (后台)
# 5. 启动 JetBrains remote-dev-server (前台)

set -e

echo "=========================================="
echo "Gitspace JetBrains 初始化开始"
echo "=========================================="

# 环境变量
# 对齐 Docker Gitspace: 使用 HOME 目录
HOME_DIR="${HOME:-/home/vscode}"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
REPO_NAME="${REPO_NAME:-repo}"
IDE_TYPE="${IDE_TYPE:-intellij}"
SSH_PORT="${SSH_PORT:-8090}"

# JetBrains 相关
JETBRAINS_IDE_DIR="${HOME}/.jetbrains-ide"
IDE_DOWNLOAD_URL_AMD64="${IDE_DOWNLOAD_URL_AMD64:-}"
IDE_DOWNLOAD_URL_ARM64="${IDE_DOWNLOAD_URL_ARM64:-}"
IDE_DIR_NAME="${IDE_DIR_NAME:-}"
JETBRAINS_PLUGINS="${JETBRAINS_PLUGINS:-}"

# 向后兼容: 如果设置了 WORKSPACE_DIR, 打印警告
if [ -n "${WORKSPACE_DIR:-}" ] && [ "$WORKSPACE_DIR" != "$HOME_DIR" ]; then
    echo "[WARN] WORKSPACE_DIR is deprecated. Using HOME=$HOME_DIR for Docker Gitspace compatibility"
fi

echo "配置信息:"
echo "  - Home: ${HOME_DIR}"
echo "  - Repository: ${REPO_NAME}"
echo "  - Branch: ${BRANCH}"
echo "  - IDE Type: ${IDE_TYPE}"
echo "  - SSH Port: ${SSH_PORT}"
echo "  - IDE Dir: ${JETBRAINS_IDE_DIR}"

# 1. 配置 Git 凭证（必须在克隆前配置，尤其是私有仓库）
if [ -n "${GIT_USERNAME:-}" ] && [ -n "${GIT_PASSWORD:-}" ]; then
    echo ""
    echo "=========================================="
    echo "步骤 1: 配置 Git 凭证"
    echo "=========================================="

    if [ -f "/usr/local/gitspace/scripts/common/setup-git-credentials.sh" ]; then
        /usr/local/gitspace/scripts/common/setup-git-credentials.sh
        echo "✓ Git 凭证配置完成"
    else
        echo "⚠ Git 凭证配置脚本不存在，跳过"
    fi
fi

# 2. 克隆代码仓库
if [ -n "${REPO_URL}" ]; then
    echo ""
    echo "=========================================="
    echo "步骤 2: 克隆代码仓库"
    echo "=========================================="

    REPO_DIR="${HOME_DIR}/${REPO_NAME}"

    if [ -d "${REPO_DIR}/.git" ]; then
        echo "✓ 仓库已存在: ${REPO_DIR}"
    else
        echo "克隆仓库到: ${REPO_DIR}"
        mkdir -p "${HOME_DIR}"

        # 使用通用克隆脚本
        if [ -f "/usr/local/gitspace/scripts/common/clone-repository.sh" ]; then
            # clone-repository.sh 使用 HOME 环境变量
            /usr/local/gitspace/scripts/common/clone-repository.sh
        else
            # 回退到简单 git clone
            git clone --branch "${BRANCH}" "${REPO_URL}" "${REPO_DIR}" || {
                echo "✗ 克隆失败，使用默认分支重试..."
                git clone "${REPO_URL}" "${REPO_DIR}"
                cd "${REPO_DIR}" && git checkout "${BRANCH}" || echo "警告: 无法切换到分支 ${BRANCH}"
            }
        fi

        echo "✓ 仓库克隆完成"
    fi
fi

# 3. 配置 SSH Server（JetBrains 使用 SSH 连接）
echo ""
echo "=========================================="
echo "步骤 3: 配置 SSH Server"
echo "=========================================="

# 确保 SSH 目录存在
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 如果提供了 SSH 公钥，配置 authorized_keys
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    echo "配置 SSH 公钥认证..."
    echo "${SSH_PUBLIC_KEY}" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "✓ SSH 公钥已配置"
else
    echo "⚠ 未提供 SSH 公钥，使用密码认证（开发环境）"
fi

# 配置 SSH Server
if [ -f "/etc/ssh/sshd_config" ]; then
    echo "配置 SSH Server 参数..."
    # 允许密码认证（开发环境）
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true
    sudo sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config || true
    echo "✓ SSH Server 配置完成"
fi

# 4. 启动 SSH Server (后台)
echo ""
echo "=========================================="
echo "步骤 4: 启动 SSH Server (后台)"
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

# 5. 确定 IDE 路径
echo ""
echo "=========================================="
echo "步骤 5: 确定 JetBrains IDE 路径"
echo "=========================================="

IDE_PATH=""
DEFAULT_IDE_PATH="${DEFAULT_IDE_PATH:-/opt/jetbrains}"
CUSTOM_IDE_PATH="${HOME}/.jetbrains-ide"

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

# 6. 安装插件（如果配置）
if [ -n "$JETBRAINS_PLUGINS" ]; then
    echo ""
    echo "=========================================="
    echo "步骤 6: 安装 JetBrains 插件"
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

# 7. 启动 JetBrains remote-dev-server (前台)
echo ""
echo "=========================================="
echo "步骤 7: 启动 JetBrains remote-dev-server"
echo "=========================================="

# 查找 remote-dev-server.sh
REMOTE_DEV_SERVER="${IDE_PATH}/bin/remote-dev-server.sh"
if [ ! -f "$REMOTE_DEV_SERVER" ]; then
    echo "✗ 未找到 remote-dev-server.sh: $REMOTE_DEV_SERVER"
    exit 1
fi

# 项目路径
PROJECT_PATH="${HOME_DIR}/${REPO_NAME}"
if [ ! -d "$PROJECT_PATH" ]; then
    echo "⚠ 项目路径不存在: $PROJECT_PATH，使用 HOME"
    PROJECT_PATH="$HOME_DIR"
fi

echo ""
echo "=========================================="
echo "初始化完成！启动 JetBrains IDE"
echo "=========================================="
echo "连接信息:"
echo "  - IDE Type: ${IDE_TYPE}"
echo "  - SSH Host: <gitspace-pod-ip>"
echo "  - SSH Port: ${SSH_PORT}"
echo "  - SSH User: vscode"
echo "  - Project: ${PROJECT_PATH}"
echo ""
echo "JetBrains Gateway 连接配置:"
echo "  SSH Host: <gitspace-url>"
echo "  SSH Port: ${SSH_PORT}"
echo "  SSH User: vscode"
echo "  Project Path: ${PROJECT_PATH}"
echo "=========================================="

echo "启动 remote-dev-server..."
echo "  IDE: $IDE_PATH"
echo "  Project: $PROJECT_PATH"
echo "  SSH Port: $SSH_PORT"
echo ""

# 启动 remote-dev-server（前台运行，作为主进程）
exec "$REMOTE_DEV_SERVER" run "$PROJECT_PATH" --ssh-link-host 0.0.0.0 --ssh-link-port "$SSH_PORT"
