#!/bin/bash
# 快速测试 Gitspace 镜像
# 用法: ./test-images.sh [registry] [tag]

set -euo pipefail

# 默认参数
REGISTRY="${1:-ttl.sh/ysicing/gitspace-runtime}"
TAG="${2:-latest}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    log_success "Docker 已安装"
}

# 检查镜像是否存在
check_image() {
    local image="$1"
    log_info "检查镜像: $image"

    if docker manifest inspect "$image" &> /dev/null; then
        log_success "镜像存在: $image"
        return 0
    else
        log_warning "镜像不存在: $image"
        return 1
    fi
}

# 拉取镜像
pull_image() {
    local image="$1"
    log_info "拉取镜像: $image"
    if docker pull "$image"; then
        log_success "镜像拉取成功: $image"
        return 0
    else
        log_error "镜像拉取失败: $image"
        return 1
    fi
}

# 测试镜像基本功能
test_image() {
    local image="$1"
    local name="$2"
    log_info "测试 $name 镜像: $image"

    # 测试基本命令
    if docker run --rm "$image" which git &> /dev/null; then
        log_success "$name: Git 命令可用"
    else
        log_error "$name: Git 命令不可用"
        return 1
    fi

    # 测试 bash
    if docker run --rm "$image" bash --version &> /dev/null; then
        log_success "$name: Bash 可用"
    else
        log_warning "$name: Bash 不可用"
    fi

    # 测试 curl
    if docker run --rm "$image" curl --version &> /dev/null; then
        log_success "$name: Curl 可用"
    else
        log_warning "$name: Curl 不可用"
    fi

    log_success "$name 镜像测试通过"
    echo ""
}

# 测试 VSCode 镜像特定功能
test_vscode_image() {
    local image="$1"
    log_info "测试 VSCode 镜像特定功能: $image"

    # 检查 code-server
    if docker run --rm "$image" which code-server &> /dev/null; then
        log_success "VSCode: code-server 已安装"
    else
        log_warning "VSCode: code-server 未安装"
    fi

    # 检查 Python
    if docker run --rm "$image" python3 --version &> /dev/null; then
        local version
        version=$(docker run --rm "$image" python3 --version)
        log_success "VSCode: Python3 可用 ($version)"
    else
        log_warning "VSCode: Python3 不可用"
    fi

    # 检查 Node.js
    if docker run --rm "$image" node --version &> /dev/null; then
        local version
        version=$(docker run --rm "$image" node --version)
        log_success "VSCode: Node.js 可用 ($version)"
    else
        log_warning "VSCode: Node.js 不可用"
    fi

    echo ""
}

# 登录 Registry（如果需要）
login_registry() {
    local registry="$1"

    if [[ "$registry" == ghcr.io* ]]; then
        log_info "需要登录 GitHub Container Registry"
        if [ -z "${GHCR_TOKEN:-}" ]; then
            log_warning "未设置 GHCR_TOKEN 环境变量"
            log_info "请运行: export GHCR_TOKEN=你的_token"
            log_info "获取 token: https://github.com/settings/tokens"
            return 1
        fi
        echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
        log_success "已登录 GitHub Container Registry"
    elif [[ "$registry" == ttl.sh* ]]; then
        log_info "ttl.sh 不需要登录"
    fi
}

# 显示镜像信息
show_image_info() {
    local image="$1"
    log_info "镜像信息: $image"

    # 获取镜像大小
    local size
    size=$(docker manifest inspect "$image" | jq -r '.config.size // "N/A"')
    echo "  大小: $(numfmt --to=iec $size 2>/dev/null || echo "$size bytes")"

    # 获取镜像架构
    local arch
    arch=$(docker manifest inspect "$image" | jq -r '.config.architecture // "N/A"')
    echo "  架构: $arch"

    # 获取创建时间
    local created
    created=$(docker manifest inspect "$image" | jq -r '.config.created // "N/A"')
    echo "  创建时间: $created"
    echo ""
}

# 主函数
main() {
    echo "================================"
    echo "Gitspace 镜像测试工具"
    echo "================================"
    echo ""
    log_info "Registry: $REGISTRY"
    log_info "Tag: $TAG"
    echo ""

    # 检查 Docker
    check_docker
    echo ""

    # 登录 Registry
    login_registry "$REGISTRY" || true
    echo ""

    # 定义镜像列表
    local images=(
        "base:Base 基础镜像"
        "vscode:VSCode 镜像"
        "jetbrains:JetBrains 镜像"
        "cursor:Cursor 镜像"
    )

    # 测试每个镜像
    for item in "${images[@]}"; do
        local type="${item%%:*}"
        local desc="${item##*:}"
        local full_image="$REGISTRY:$type-$TAG"

        echo "----------------------------------------"
        log_info "测试 $desc ($type)"
        echo "----------------------------------------"

        # 显示镜像信息
        show_image_info "$full_image"

        # 尝试拉取镜像
        if ! pull_image "$full_image"; then
            log_error "跳过测试: $full_image"
            echo ""
            continue
        fi

        # 测试镜像
        if ! test_image "$full_image" "$desc"; then
            log_error "测试失败: $full_image"
            echo ""
            continue
        fi

        # 如果是 VSCode，额外测试
        if [ "$type" = "vscode" ]; then
            test_vscode_image "$full_image"
        fi

        echo ""
    done

    echo "================================"
    log_success "所有测试完成!"
    echo "================================"
    echo ""
    log_info "快速启动命令:"
    echo "  # 启动 VSCode"
    echo "  docker run -d -p 8080:8080 $REGISTRY:vscode-$TAG"
    echo ""
    echo "  # 启动 JetBrains"
    echo "  docker run -d -p 8080:8080 $REGISTRY:jetbrains-$TAG"
    echo ""
}

# 显示帮助
show_help() {
    cat <<EOF
用法: $0 [registry] [tag]

参数:
  registry  镜像仓库地址 (默认: ttl.sh/ysicing/gitspace-runtime)
  tag       镜像标签 (默认: latest)

示例:
  # 测试 ttl.sh 镜像
  $0

  # 测试 ghcr.io 镜像
  $0 ghcr.io/ysicing/gitspace-runtime latest

  # 测试特定标签
  $0 ttl.sh/ysicing/gitspace-runtime 123456789

环境变量:
  GHCR_TOKEN    GitHub Container Registry 访问令牌
  GITHUB_ACTOR  GitHub 用户名 (自动设置)

EOF
}

# 如果没有参数或第一个参数是 -h/--help，显示帮助
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# 运行主函数
main
