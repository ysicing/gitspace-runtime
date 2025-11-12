#!/bin/bash
# 安装 zsh 自定义插件到 ZSH_CUSTOM 目录
# 注意：目录 /opt/zsh-custom/plugins 和 /opt/zsh-custom/themes 应该在运行此脚本前已创建
set -euo pipefail

ZSH_CUSTOM_DIR="/opt/zsh-custom"
PLUGINS_DIR="$ZSH_CUSTOM_DIR/plugins"

echo "==> Installing zsh custom plugins to $PLUGINS_DIR"

# 验证目录存在
if [ ! -d "$PLUGINS_DIR" ]; then
    echo "ERROR: Directory $PLUGINS_DIR does not exist. Please create it first." >&2
    exit 1
fi

# 安装自定义插件
echo "==> Installing zsh-autosuggestions..."
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
    "$PLUGINS_DIR/zsh-autosuggestions"

echo "==> Installing fast-syntax-highlighting..."
git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
    "$PLUGINS_DIR/fast-syntax-highlighting"

echo "==> Installing zsh-autocomplete..."
git clone --depth=1 https://github.com/marlonrichert/zsh-autocomplete.git \
    "$PLUGINS_DIR/zsh-autocomplete"

echo "==> Installing zsh-syntax-highlighting (backup)..."
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$PLUGINS_DIR/zsh-syntax-highlighting"

# 设置权限
chmod -R 755 "$PLUGINS_DIR"

echo "✓ zsh custom plugins installed to $PLUGINS_DIR"
echo "✓ Plugins installed:"
echo "  - zsh-autosuggestions"
echo "  - fast-syntax-highlighting"
echo "  - zsh-autocomplete"
echo "  - zsh-syntax-highlighting"

