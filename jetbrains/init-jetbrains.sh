#!/bin/bash
# Copyright (c) 2025-2025 All rights reserved.
#
# Gitspace JetBrains InitContainer 初始化脚本
# 负责：
# 1. 配置 Git 凭证
# 2. 克隆代码仓库
# 3. 配置 SSH 认证（JetBrains 需要 SSH 连接）
# 4. 下载 JetBrains IDE（如果需要）

set -e

echo "=========================================="
echo "Gitspace JetBrains 初始化开始"
echo "=========================================="

# 环境变量
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
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

echo "配置信息:"
echo "  - Workspace: ${WORKSPACE_DIR}"
echo "  - Repository: ${REPO_NAME}"
echo "  - Branch: ${BRANCH}"
echo "  - IDE Type: ${IDE_TYPE}"
echo "  - SSH Port: ${SSH_PORT}"
echo "  - IDE Dir: ${JETBRAINS_IDE_DIR}"

# 1. 配置 Git 凭证（必须在克隆前配置，尤其是私有仓库）
if [ -n "${GIT_USERNAME}" ] && [ -n "${GIT_PASSWORD}" ]; then
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

    REPO_DIR="${WORKSPACE_DIR}/${REPO_NAME}"

    if [ -d "${REPO_DIR}/.git" ]; then
        echo "✓ 仓库已存在: ${REPO_DIR}"
    else
        echo "克隆仓库到: ${REPO_DIR}"
        mkdir -p "${WORKSPACE_DIR}"

        # 使用通用克隆脚本
        if [ -f "/usr/local/gitspace/scripts/common/clone-code.sh" ]; then
            export CODE_REPO_URL="${REPO_URL}"
            export CODE_REPO_BRANCH="${BRANCH}"
            export HOME_DIR="${WORKSPACE_DIR}"
            /usr/local/gitspace/scripts/common/clone-code.sh
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
if [ -n "${SSH_PUBLIC_KEY}" ]; then
    echo "配置 SSH 公钥认证..."
    echo "${SSH_PUBLIC_KEY}" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "✓ SSH 公钥已配置"
else
    echo "⚠ 未提供 SSH 公钥，使用密码认证（开发环境）"
fi

echo "✓ SSH 配置完成"

# 4. 下载 JetBrains IDE（如果需要且未预装）
echo ""
echo "=========================================="
echo "步骤 4: 检查 JetBrains IDE"
echo "=========================================="

if [ -n "${IDE_DOWNLOAD_URL_AMD64}" ] || [ -n "${IDE_DOWNLOAD_URL_ARM64}" ]; then
    echo "配置了 IDE 下载 URL，将在主容器启动时下载"
else
    echo "未配置 IDE 下载 URL，将使用预装或默认 IDE"
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
echo "JetBrains Gateway 连接配置:"
echo "  IDE Type: ${IDE_TYPE}"
echo "  SSH Host: <gitspace-url>"
echo "  SSH Port: ${SSH_PORT}"
echo "  SSH User: vscode"
echo "  Project Path: ${WORKSPACE_DIR}/${REPO_NAME}"
echo "=========================================="
