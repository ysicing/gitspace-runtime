#!/bin/bash
# Docker vs K8s Gitspace 一致性验证脚本
# 用于验证 Docker 和 K8s 部署的行为一致性

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

PASSED=0
FAILED=0
WARNINGS=0

echo "=========================================="
echo "Docker vs K8s Gitspace 一致性验证"
echo "=========================================="
echo ""

# ========================================
# 辅助函数
# ========================================

test_pass() {
    local name="$1"
    echo -e "${GREEN}✓${NC} $name"
    ((PASSED++))
}

test_fail() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    echo -e "${RED}✗${NC} $name"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    ((FAILED++))
}

test_warn() {
    local name="$1"
    local message="$2"
    echo -e "${YELLOW}⚠${NC} $name: $message"
    ((WARNINGS++))
}

test_section() {
    local name="$1"
    echo ""
    echo -e "${BLUE}=== $name ===${NC}"
}

# ========================================
# 参数解析
# ========================================

DOCKER_CONTAINER="${1:-}"
K8S_POD="${2:-}"
K8S_NAMESPACE="${3:-gitspace-demo}"

if [ -z "$DOCKER_CONTAINER" ] || [ -z "$K8S_POD" ]; then
    echo "用法: $0 <docker-container-name> <k8s-pod-name> [k8s-namespace]"
    echo ""
    echo "示例:"
    echo "  $0 gitspace-vscode-demo gitspace-vscode-xxx gitspace-demo"
    echo ""
    echo "提示:"
    echo "  - Docker 容器: docker ps"
    echo "  - K8s Pod: kubectl get pods -n gitspace-demo"
    exit 1
fi

# 检查 Docker 容器是否存在
if ! docker ps --filter "name=$DOCKER_CONTAINER" --format "{{.Names}}" | grep -q "$DOCKER_CONTAINER"; then
    echo -e "${RED}错误: Docker 容器 '$DOCKER_CONTAINER' 不存在或未运行${NC}"
    exit 1
fi

# 检查 K8s Pod 是否存在
if ! kubectl get pod "$K8S_POD" -n "$K8S_NAMESPACE" &>/dev/null; then
    echo -e "${RED}错误: K8s Pod '$K8S_POD' 在命名空间 '$K8S_NAMESPACE' 中不存在${NC}"
    exit 1
fi

echo "Docker 容器: $DOCKER_CONTAINER"
echo "K8s Pod: $K8S_POD (namespace: $K8S_NAMESPACE)"
echo ""

# ========================================
# 测试 1: 挂载点检查
# ========================================

test_section "1. 持久化卷挂载点"

# Docker 挂载点
docker_mounts=$(docker inspect "$DOCKER_CONTAINER" | jq -r '.[0].Mounts[] | select(.Type == "volume") | .Destination')
docker_home_mounted=false
if echo "$docker_mounts" | grep -q "^/home/"; then
    docker_home_mounted=true
    docker_mount_point=$(echo "$docker_mounts" | grep "^/home/" | head -1)
    test_pass "Docker 挂载到 HOME 目录: $docker_mount_point"
else
    test_fail "Docker 挂载点" "/home/{username}" "$docker_mounts"
fi

# K8s 挂载点
k8s_mounts=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c "mount | grep -E '/(home|workspaces)' || true")
k8s_home_mounted=false
if echo "$k8s_mounts" | grep -q "/home/"; then
    k8s_home_mounted=true
    k8s_mount_point=$(echo "$k8s_mounts" | grep "/home/" | awk '{print $3}' | head -1)
    test_pass "K8s 挂载到 HOME 目录: $k8s_mount_point"
else
    test_fail "K8s 挂载点" "/home/{username}" "$(echo "$k8s_mounts" | head -1)"
fi

# 对比
if [ "$docker_home_mounted" = true ] && [ "$k8s_home_mounted" = true ]; then
    test_pass "挂载策略一致 (都挂载到 HOME)"
elif [ "$docker_home_mounted" = false ] && [ "$k8s_home_mounted" = false ]; then
    test_warn "挂载策略一致" "但都未挂载到 HOME (不推荐)"
else
    test_fail "挂载策略一致性" "相同" "不同 (Docker: $docker_home_mounted, K8s: $k8s_home_mounted)"
fi

# ========================================
# 测试 2: 工作目录检查
# ========================================

test_section "2. 工作目录 (Working Directory)"

docker_workdir=$(docker exec "$DOCKER_CONTAINER" pwd)
k8s_workdir=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- pwd)

echo "  Docker 工作目录: $docker_workdir"
echo "  K8s 工作目录:    $k8s_workdir"

if [[ "$docker_workdir" == /home/* ]] && [[ "$k8s_workdir" == /home/* ]]; then
    test_pass "工作目录都在 HOME 下"
elif [[ "$docker_workdir" == /workspaces/* ]] && [[ "$k8s_workdir" == /workspaces/* ]]; then
    test_warn "工作目录一致" "但都在 /workspaces (不推荐, 应使用 HOME)"
elif [ "$docker_workdir" = "$k8s_workdir" ]; then
    test_pass "工作目录一致: $docker_workdir"
else
    test_fail "工作目录一致性" "$docker_workdir" "$k8s_workdir"
fi

# ========================================
# 测试 3: 用户身份检查
# ========================================

test_section "3. 用户身份 (User Identity)"

docker_user=$(docker exec "$DOCKER_CONTAINER" id)
k8s_user=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- id)

echo "  Docker 用户: $docker_user"
echo "  K8s 用户:    $k8s_user"

# 提取 UID
docker_uid=$(echo "$docker_user" | grep -oP 'uid=\K\d+')
k8s_uid=$(echo "$k8s_user" | grep -oP 'uid=\K\d+')

if [ "$docker_uid" = "$k8s_uid" ]; then
    test_pass "UID 一致: $docker_uid"
else
    test_fail "UID 一致性" "$docker_uid" "$k8s_uid"
fi

# 提取 GID
docker_gid=$(echo "$docker_user" | grep -oP 'gid=\K\d+')
k8s_gid=$(echo "$k8s_user" | grep -oP 'gid=\K\d+')

if [ "$docker_gid" = "$k8s_gid" ]; then
    test_pass "GID 一致: $docker_gid"
else
    test_fail "GID 一致性" "$docker_gid" "$k8s_gid"
fi

# ========================================
# 测试 4: HOME 目录检查
# ========================================

test_section "4. HOME 环境变量"

docker_home=$(docker exec "$DOCKER_CONTAINER" sh -c 'echo $HOME')
k8s_home=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c 'echo $HOME')

echo "  Docker HOME: $docker_home"
echo "  K8s HOME:    $k8s_home"

if [ "$docker_home" = "$k8s_home" ]; then
    test_pass "HOME 环境变量一致: $docker_home"
else
    test_fail "HOME 环境变量一致性" "$docker_home" "$k8s_home"
fi

# ========================================
# 测试 5: 代码仓库路径检查
# ========================================

test_section "5. 代码仓库路径"

# 尝试查找 .git 目录
docker_repos=$(docker exec "$DOCKER_CONTAINER" sh -c 'find /home -maxdepth 3 -name .git -type d 2>/dev/null | head -5 | sed "s|/.git||" || true')
k8s_repos=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c 'find /home -maxdepth 3 -name .git -type d 2>/dev/null | head -5 | sed "s|/.git||" || true')

if [ -n "$docker_repos" ] && [ -n "$k8s_repos" ]; then
    echo "  Docker 仓库: $docker_repos"
    echo "  K8s 仓库:    $k8s_repos"

    # 检查是否都在 HOME 下
    docker_in_home=$(echo "$docker_repos" | grep -c "^/home/" || echo "0")
    k8s_in_home=$(echo "$k8s_repos" | grep -c "^/home/" || echo "0")

    if [ "$docker_in_home" -gt 0 ] && [ "$k8s_in_home" -gt 0 ]; then
        test_pass "代码仓库都在 HOME 目录下"
    else
        test_warn "代码仓库路径" "不都在 HOME 目录下"
    fi
else
    test_warn "代码仓库" "未找到 .git 目录 (可能尚未克隆)"
fi

# ========================================
# 测试 6: 用户配置文件持久化检查
# ========================================

test_section "6. 用户配置文件"

# 检查常见配置文件
config_files=(".bashrc" ".profile" ".gitconfig")

for config_file in "${config_files[@]}"; do
    docker_exists=$(docker exec "$DOCKER_CONTAINER" sh -c "test -f \$HOME/$config_file && echo 'yes' || echo 'no'")
    k8s_exists=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c "test -f \$HOME/$config_file && echo 'yes' || echo 'no'")

    if [ "$docker_exists" = "yes" ] && [ "$k8s_exists" = "yes" ]; then
        test_pass "$config_file 存在 (Docker 和 K8s)"
    elif [ "$docker_exists" = "$k8s_exists" ]; then
        test_pass "$config_file 状态一致 (都不存在)"
    else
        test_warn "$config_file" "存在性不一致 (Docker: $docker_exists, K8s: $k8s_exists)"
    fi
done

# ========================================
# 测试 7: VS Code Server 持久化检查
# ========================================

test_section "7. VS Code Server 数据"

docker_vscode=$(docker exec "$DOCKER_CONTAINER" sh -c "test -d \$HOME/.vscode-server && echo 'yes' || echo 'no'")
k8s_vscode=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c "test -d \$HOME/.vscode-server && echo 'yes' || echo 'no'")

if [ "$docker_vscode" = "yes" ] && [ "$k8s_vscode" = "yes" ]; then
    test_pass ".vscode-server 目录存在 (Docker 和 K8s)"

    # 检查 data 目录
    docker_data=$(docker exec "$DOCKER_CONTAINER" sh -c "test -d \$HOME/.vscode-server/data && echo 'yes' || echo 'no'")
    k8s_data=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c "test -d \$HOME/.vscode-server/data && echo 'yes' || echo 'no'")

    if [ "$docker_data" = "yes" ] && [ "$k8s_data" = "yes" ]; then
        test_pass ".vscode-server/data 目录存在 (用户数据持久化)"
    else
        test_warn ".vscode-server/data" "存在性不一致 (Docker: $docker_data, K8s: $k8s_data)"
    fi
else
    test_warn ".vscode-server" "目录不存在 (可能尚未启动 IDE)"
fi

# ========================================
# 测试 8: 向后兼容性检查
# ========================================

test_section "8. 向后兼容 (/workspaces 符号链接)"

# 检查 /workspaces 是否存在且是符号链接
k8s_workspaces_link=$(kubectl exec "$K8S_POD" -n "$K8S_NAMESPACE" -- sh -c "test -L /workspaces && readlink /workspaces || echo 'not-a-link'")

if [[ "$k8s_workspaces_link" == /home/* ]]; then
    test_pass "K8s /workspaces 是符号链接指向: $k8s_workspaces_link"
elif [ "$k8s_workspaces_link" = "not-a-link" ]; then
    test_warn "/workspaces" "不是符号链接 (可能是直接挂载或不存在)"
else
    test_warn "/workspaces" "符号链接目标不在 HOME: $k8s_workspaces_link"
fi

# ========================================
# 总结
# ========================================

echo ""
echo "=========================================="
echo "测试总结"
echo "=========================================="
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${RED}失败: $FAILED${NC}"
echo -e "${YELLOW}警告: $WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ 完美! Docker 和 K8s 完全一致!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Docker 和 K8s 基本一致, 但有 $WARNINGS 个警告${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ 发现 $FAILED 个不一致, 请检查配置${NC}"
    exit 1
fi
