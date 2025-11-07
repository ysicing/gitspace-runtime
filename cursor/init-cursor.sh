#!/bin/bash
# Copyright (c) 2025-2025 All rights reserved.
#
# Gitspace Cursor/Windsurf 初始化并启动脚本
# 负责：
# 1. 配置 Git 凭证
# 2. 克隆代码仓库
# 3. 配置 SSH Server
# 4. 启动 SSH Server（供 Cursor/Windsurf Remote-SSH 连接）

set -e

echo "=========================================="
echo "Gitspace Cursor/Windsurf 初始化开始"
echo "=========================================="

# 环境变量
# 对齐 Docker Gitspace: 使用 HOME 目录
HOME_DIR="${HOME:-/home/vscode}"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
REPO_NAME="${REPO_NAME:-repo}"
IDE_TYPE="${IDE_TYPE:-cursor}"
SSH_PORT="${SSH_PORT:-8098}"

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

# 3. 配置 SSH Server（Cursor/Windsurf 使用 SSH 连接）
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
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true
    sudo sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config || true
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
if [ "${IDE_TYPE}" = "cursor" ]; then
    echo "Cursor Remote-SSH 连接配置:"
elif [ "${IDE_TYPE}" = "windsurf" ]; then
    echo "Windsurf Remote-SSH 连接配置:"
else
    echo "Remote-SSH 连接配置:"
fi
echo "  Host gitspace-${REPO_NAME}"
echo "    HostName <gitspace-url>"
echo "    Port ${SSH_PORT}"
echo "    User vscode"
echo "    IdentityFile ~/.ssh/id_rsa (如果使用 SSH key)"
echo "=========================================="
echo ""
echo "正在启动 SSH Server..."

# 4. 启动 SSH Server（作为主进程）
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

# 确保 SSH 配置正确的端口
sudo sed -i "s/^#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
if ! grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config; then
    echo "Port ${SSH_PORT}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

echo "✓ Starting SSH Server in foreground mode on port ${SSH_PORT}..."

# 启动 SSH Server（前台模式，作为主进程）
exec sudo /usr/sbin/sshd -D -p "${SSH_PORT}"
