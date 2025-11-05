#!/bin/bash
# 测试用户检测和创建功能
# 验证不同场景下的用户模型动态化

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "=========================================="
echo "用户模型动态化测试"
echo "=========================================="
echo ""

# 创建临时测试目录
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

cd "$TEST_DIR"

# 测试函数
test_case() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $name: $actual"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((FAILED++))
    fi
}

# 加载脚本
SCRIPT_DIR="/Users/ysicing/Work/github/ysicing/gitspace-runtime/base/scripts"
if [ ! -f "$SCRIPT_DIR/detect-devcontainer-user.sh" ]; then
    echo "Error: Cannot find detect-devcontainer-user.sh"
    exit 1
fi
source "$SCRIPT_DIR/detect-devcontainer-user.sh"

# ========================================
# 测试用例 1: 默认配置 (无 devcontainer.json)
# ========================================
echo -e "${BLUE}测试用例 1: 默认配置 (无 devcontainer.json)${NC}"
mkdir -p test1
eval "$(detect_devcontainer_user test1 2>&1 | grep '^export')"

test_case "Default CONTAINER_USER" "vscode" "$CONTAINER_USER"
test_case "Default REMOTE_USER" "vscode" "$REMOTE_USER"
test_case "Default USER_UID" "1000" "$USER_UID"
test_case "Default USER_GID" "1000" "$USER_GID"
test_case "Default HOME_DIR" "/home/vscode" "$HOME_DIR"
echo ""

# ========================================
# 测试用例 2: Root 用户
# ========================================
echo -e "${BLUE}测试用例 2: Root 用户${NC}"
mkdir -p test2/.devcontainer
cat > test2/.devcontainer/devcontainer.json <<EOF
{
  "name": "Root Container",
  "image": "ubuntu:22.04",
  "containerUser": "root",
  "remoteUser": "root"
}
EOF

eval "$(detect_devcontainer_user test2 2>/dev/null)"

test_case "Root CONTAINER_USER" "root" "$CONTAINER_USER"
test_case "Root REMOTE_USER" "root" "$REMOTE_USER"
test_case "Root HOME_DIR" "/root" "$HOME_DIR"
echo ""

# ========================================
# 测试用例 3: 自定义用户名
# ========================================
echo -e "${BLUE}测试用例 3: 自定义用户名${NC}"
mkdir -p test3/.devcontainer
cat > test3/.devcontainer/devcontainer.json <<EOF
{
  "name": "Node.js Dev",
  "image": "node:18",
  "containerUser": "node",
  "remoteUser": "developer"
}
EOF

eval "$(detect_devcontainer_user test3 2>/dev/null)"

test_case "Custom CONTAINER_USER" "node" "$CONTAINER_USER"
test_case "Custom REMOTE_USER" "developer" "$REMOTE_USER"
test_case "Custom HOME_DIR" "/home/developer" "$HOME_DIR"
echo ""

# ========================================
# 测试用例 4: 显式 UID:GID
# ========================================
echo -e "${BLUE}测试用例 4: 显式 UID:GID${NC}"
mkdir -p test4/.devcontainer
cat > test4/.devcontainer/devcontainer.json <<EOF
{
  "name": "Custom UID",
  "image": "custom:latest",
  "containerUser": "1001:1001",
  "remoteUser": "developer"
}
EOF

eval "$(detect_devcontainer_user test4 2>/dev/null)"

test_case "Explicit USER_UID" "1001" "$USER_UID"
test_case "Explicit USER_GID" "1001" "$USER_GID"
test_case "Explicit REMOTE_USER" "developer" "$REMOTE_USER"
echo ""

# ========================================
# 测试用例 5: 仅 containerUser (remoteUser 继承)
# ========================================
echo -e "${BLUE}测试用例 5: 仅 containerUser (remoteUser 继承)${NC}"
mkdir -p test5/.devcontainer
cat > test5/.devcontainer/devcontainer.json <<EOF
{
  "name": "Only containerUser",
  "image": "python:3.11",
  "containerUser": "python"
}
EOF

eval "$(detect_devcontainer_user test5 2>/dev/null)"

test_case "Inherited REMOTE_USER" "$CONTAINER_USER" "$REMOTE_USER"
echo ""

# ========================================
# 测试用例 6: 环境变量覆盖
# ========================================
echo -e "${BLUE}测试用例 6: 环境变量覆盖${NC}"
mkdir -p test6/.devcontainer
cat > test6/.devcontainer/devcontainer.json <<EOF
{
  "name": "Default Config",
  "image": "base:latest",
  "containerUser": "default",
  "remoteUser": "default"
}
EOF

export CONTAINER_USER="override"
export REMOTE_USER="override-remote"
export USER_UID="2000"
export USER_GID="2000"

eval "$(detect_devcontainer_user test6 2>/dev/null)"

# 注意: 当前实现,devcontainer.json 优先级高于环境变量
# 如果需要环境变量优先,需要修改脚本逻辑
test_case "Env CONTAINER_USER (from devcontainer)" "default" "$CONTAINER_USER"
test_case "Env REMOTE_USER (from devcontainer)" "default" "$REMOTE_USER"

# 清理环境变量
unset CONTAINER_USER REMOTE_USER USER_UID USER_GID
echo ""

# ========================================
# 汇总
# ========================================
echo "=========================================="
echo "测试汇总"
echo "=========================================="
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${RED}失败: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过!${NC}"
    exit 0
else
    echo -e "${RED}✗ 发现 $FAILED 个失败,请检查实现${NC}"
    exit 1
fi
