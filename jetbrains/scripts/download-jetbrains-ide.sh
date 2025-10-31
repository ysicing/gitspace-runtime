#!/bin/bash
# 下载 JetBrains IDE

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

# ========================================
# 检测架构
# ========================================
is_arm() {
    case "$(uname -m)" in
        arm* | aarch64) return 0 ;;
        *) return 1 ;;
    esac
}

# ========================================
# 获取 IDE 下载 URL
# ========================================
get_ide_download_url() {
    local ide_type="${IDE_TYPE:-intellij}"
    local arch="linux"

    if is_arm; then
        arch="linuxARM64"
        log_info "Detected ARM architecture"
    else
        log_info "Detected x86_64 architecture"
    fi

    # IDE 下载 URL 映射
    # 如果环境变量提供了自定义 URL，使用自定义 URL
    if [ -n "${JETBRAINS_IDE_DOWNLOAD_URL:-}" ]; then
        echo "$JETBRAINS_IDE_DOWNLOAD_URL"
        return
    fi

    # 默认使用最新版本
    case "$ide_type" in
        intellij|intellij-idea)
            echo "https://download.jetbrains.com/idea/ideaIU-latest-$arch.tar.gz"
            ;;
        pycharm)
            echo "https://download.jetbrains.com/python/pycharm-professional-latest-$arch.tar.gz"
            ;;
        goland)
            echo "https://download.jetbrains.com/go/goland-latest-$arch.tar.gz"
            ;;
        webstorm)
            echo "https://download.jetbrains.com/webstorm/WebStorm-latest-$arch.tar.gz"
            ;;
        phpstorm)
            echo "https://download.jetbrains.com/webide/PhpStorm-latest-$arch.tar.gz"
            ;;
        clion)
            echo "https://download.jetbrains.com/cpp/CLion-latest-$arch.tar.gz"
            ;;
        rubymine)
            echo "https://download.jetbrains.com/ruby/RubyMine-latest-$arch.tar.gz"
            ;;
        rider)
            echo "https://download.jetbrains.com/rider/JetBrains.Rider-latest-$arch.tar.gz"
            ;;
        *)
            log_error "Unsupported IDE type: $ide_type"
            return 1
            ;;
    esac
}

# ========================================
# 下载并安装 IDE
# ========================================
download_jetbrains_ide() {
    local ide_dir="${JETBRAINS_IDE_DIR:-$HOME/.jetbrains-ide}"
    local tmp_dir="${TMP_DOWNLOAD_DIR:-/tmp/jetbrains-download}"

    # 检查是否已安装
    if [ -d "$ide_dir" ] && [ -f "$ide_dir/bin/remote-dev-server.sh" ]; then
        log_info "JetBrains IDE already installed at $ide_dir"
        return 0
    fi

    # 获取下载 URL
    local download_url
    download_url=$(get_ide_download_url)

    if [ -z "$download_url" ]; then
        log_error "Failed to determine IDE download URL"
        return 1
    fi

    log_info "Downloading IDE from: $download_url"

    # 创建临时目录
    mkdir -p "$tmp_dir"

    # 下载 IDE
    local tarball_name
    tarball_name=$(basename "$download_url")
    local tarball_path="$tmp_dir/$tarball_name"

    log_info "Downloading to: $tarball_path"

    # 下载（带进度条）
    if ! curl -L --progress-bar -o "$tarball_path" "$download_url"; then
        log_error "Failed to download IDE from $download_url"
        return 1
    fi

    log_info "Download completed: $(du -h "$tarball_path" | cut -f1)"

    # 创建 IDE 目录
    mkdir -p "$ide_dir"

    # 解压
    log_info "Extracting IDE..."
    if ! tar -xzf "$tarball_path" -C "$ide_dir" --strip-components=1; then
        log_error "Failed to extract IDE"
        rm -rf "$ide_dir"
        return 1
    fi

    log_info "Extraction completed"

    # 验证安装
    if [ ! -f "$ide_dir/bin/remote-dev-server.sh" ]; then
        log_error "IDE installation verification failed: remote-dev-server.sh not found"
        return 1
    fi

    # 设置权限
    chmod +x "$ide_dir/bin/"*.sh

    # 清理下载文件
    log_info "Cleaning up download files..."
    rm -rf "$tmp_dir"

    log_info "JetBrains IDE installed successfully at $ide_dir"

    # 显示版本信息（如果可用）
    if [ -f "$ide_dir/product-info.json" ]; then
        local product_name
        local product_version
        product_name=$(jq -r '.name // "Unknown"' "$ide_dir/product-info.json" 2>/dev/null || echo "Unknown")
        product_version=$(jq -r '.version // "Unknown"' "$ide_dir/product-info.json" 2>/dev/null || echo "Unknown")
        log_info "Product: $product_name"
        log_info "Version: $product_version"
    fi
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    download_jetbrains_ide
fi
