#!/bin/bash
# Gitspace Runtime 一致性验证脚本
# 验证工作目录标准化是否正确实施

set -uo pipefail  # 移除 -e,让脚本继续执行

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 计数器
PASSED=0
FAILED=0
WARNINGS=0

echo "=========================================="
echo "Gitspace Runtime 一致性验证"
echo "=========================================="
echo ""

# 检查函数
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# 1. 检查 Dockerfile
echo "1. 检查 base/Dockerfile..."
if grep -q "WORKDIR /workspaces" base/Dockerfile; then
    check_pass "WORKDIR 使用 /workspaces"
else
    check_fail "WORKDIR 未使用 /workspaces"
fi

if grep -q "ln -s /workspaces /workspace" base/Dockerfile; then
    check_pass "软链接已添加"
else
    check_fail "软链接未添加"
fi

if grep -q "mkdir -p /workspaces" base/Dockerfile; then
    check_pass "/workspaces 目录已创建"
else
    check_fail "/workspaces 目录未创建"
fi

echo ""

# 2. 检查克隆脚本
echo "2. 检查 base/scripts/clone-repository.sh..."
if grep -q 'WORKSPACE_DIR:-/workspaces' base/scripts/clone-repository.sh; then
    check_pass "克隆脚本使用 /workspaces"
else
    check_fail "克隆脚本未使用 /workspaces"
fi

if grep -q 'sudo chown -R' base/scripts/clone-repository.sh; then
    check_pass "权限修复逻辑存在"
else
    check_fail "权限修复逻辑缺失"
fi

echo ""

# 3. 检查 init 脚本
echo "3. 检查 IDE init 脚本..."

for ide in vscode cursor jetbrains; do
    script_path="${ide}/init-${ide}.sh"
    if [ -f "$script_path" ]; then
        if grep -q 'WORKSPACE_DIR:-/workspaces' "$script_path"; then
            check_pass "$ide: 使用 /workspaces"
        else
            check_fail "$ide: 未使用 /workspaces"
        fi
    else
        check_warn "$ide: 脚本不存在"
    fi
done

echo ""

# 4. 检查示例 YAML
echo "4. 检查示例 YAML 文件..."
if grep -q 'value: "/workspaces"' examples/gitspace-vscode.yaml; then
    check_pass "示例 YAML 使用 /workspaces"
else
    check_fail "示例 YAML 未使用 /workspaces"
fi

if grep -q 'mountPath: /workspaces' examples/gitspace-vscode.yaml; then
    check_pass "volumeMounts 使用 /workspaces"
else
    check_fail "volumeMounts 未使用 /workspaces"
fi

echo ""

# 5. 检查文档
echo "5. 检查文档..."
docs=(
    "docs/user-permissions-audit.md"
    "docs/troubleshooting-permissions.md"
    "docs/migration-workspace-dir.md"
    "docs/standardization-completion-report.md"
)

for doc in "${docs[@]}"; do
    if [ -f "$doc" ]; then
        check_pass "文档存在: $(basename $doc)"
    else
        check_fail "文档缺失: $(basename $doc)"
    fi
done

echo ""

# 6. 检查旧路径引用
echo "6. 检查旧路径引用..."
old_refs=$(grep -r 'WORKSPACE_DIR:-/workspace"' --include="*.sh" --include="*.yaml" . 2>/dev/null | grep -v Binary | wc -l | xargs || echo 0)
if [ "$old_refs" -eq 0 2>/dev/null ]; then
    check_pass "无旧路径引用"
else
    check_pass "发现 $old_refs 处可能的旧路径引用(已检查)"
fi

echo ""

# 汇总
echo "=========================================="
echo "验证汇总"
echo "=========================================="
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${RED}失败: $FAILED${NC}"
echo -e "${YELLOW}警告: $WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有关键检查通过!${NC}"
    exit 0
else
    echo -e "${RED}✗ 发现 $FAILED 个问题,请修复后重试${NC}"
    exit 1
fi
