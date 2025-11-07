#!/bin/bash
# Copyright (c) 2025-2025 All rights reserved.
#
# Gitspace VSCode Desktop 初始化并启动脚本
# 负责：
# 1. 配置 Git 凭证
# 2. 克隆代码仓库
# 3. 配置 SSH Server
# 4. 启动 SSH Server（供 VSCode Desktop Remote-SSH 连接）

set -e

echo "=========================================="
echo "Gitspace VSCode Desktop 初始化开始"
echo "=========================================="

# 环境变量
# 对齐 Docker Gitspace: 使用 HOME 目录而不是 WORKSPACE_DIR
HOME_DIR="${HOME:-/home/vscode}"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
REPO_NAME="${REPO_NAME:-repo}"
IDE_TYPE="${IDE_TYPE:-vs_code}"
SSH_PORT="${SSH_PORT:-8088}"

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

        # 使用 /usr/local/gitspace/scripts/common/clone-repository.sh 脚本
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

# 3. 配置 SSH Server（桌面版特有）
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
# 确保 sshd_config 存在并配置正确
if [ -f "/etc/ssh/sshd_config" ]; then
    echo "配置 SSH Server 参数..."
    # 允许密码认证（开发环境）
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true
    sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config || true
    echo "✓ SSH Server 配置完成"
fi

echo ""
echo "=========================================="
echo "初始化完成！"
echo "=========================================="
echo "SSH 连接信息:"
echo "  - Host: <gitspace-pod-ip>"
echo "  - Port: ${SSH_PORT}"
echo "  - User: vscode"
echo "  - Auth: SSH Key (推荐) 或 空密码"
echo ""
echo "VSCode Remote-SSH 连接配置:"
echo "  Host gitspace-${REPO_NAME}"
echo "    HostName <gitspace-url>"
echo "    Port ${SSH_PORT}"
echo "    User vscode"
echo "    IdentityFile ~/.ssh/id_rsa (如果使用 SSH key)"
echo "=========================================="
echo ""
echo "正在启动 SSH Server..."

# 4. 启动 SSH Server（作为主进程）
# 使用 /usr/sbin/sshd -D 以前台模式运行
if [ -f "/usr/sbin/sshd" ]; then
    echo "✓ Starting SSH Server in foreground mode..."
    exec /usr/sbin/sshd -D -e
else
    echo "✗ SSH Server 不存在，请检查镜像是否正确安装了 openssh-server"
    exit 1
fi
