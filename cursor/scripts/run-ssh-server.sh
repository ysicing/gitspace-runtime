#!/bin/bash
# Copyright (c) 2025-2025 All rights reserved.
#
# 启动 Cursor/Windsurf SSH Server 脚本
# 用于主容器启动 SSH 服务
# - Cursor: 端口 8098
# - Windsurf: 端口 8099

set -e

SSH_PORT="${SSH_PORT:-8098}"

echo "启动 SSH Server..."
echo "  - Port: ${SSH_PORT}"

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

# 确保 SSH 配置正确
sudo sed -i "s/^#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
if ! grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config; then
    echo "Port ${SSH_PORT}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

echo "✓ SSH Server 配置完成"
echo "启动 sshd..."

# 启动 SSH Server（前台运行）
sudo /usr/sbin/sshd -D -p "${SSH_PORT}"
