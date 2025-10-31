#!/bin/bash
# 配置 VSCode Server 和扩展

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

configure_vscode() {
    local config_dir="$HOME/.config/code-server"
    local ide_port="${IDE_PORT:-8089}"

    # 创建配置目录
    mkdir -p "$config_dir"
    log_info "Config directory: $config_dir"

    # 创建配置文件
    cat > "$config_dir/config.yaml" <<EOF
bind-addr: 0.0.0.0:$ide_port
auth: none
cert: false
EOF
    log_info "VSCode config.yaml created"

    # 安装扩展（如果配置了）
    if [ -n "${VSCODE_EXTENSIONS:-}" ]; then
        log_info "Installing VSCode extensions..."

        # 将逗号分隔的扩展列表转换为数组
        IFS=',' read -ra EXTENSIONS <<< "$VSCODE_EXTENSIONS"

        local installed_count=0
        local failed_count=0

        for extension in "${EXTENSIONS[@]}"; do
            # 去除首尾空格
            extension=$(echo "$extension" | xargs)

            if [ -z "$extension" ]; then
                continue
            fi

            log_info "Installing extension: $extension"

            if code-server --install-extension "$extension" 2>&1; then
                installed_count=$((installed_count + 1))
                log_info "✓ Successfully installed: $extension"
            else
                failed_count=$((failed_count + 1))
                log_error "✗ Failed to install: $extension"
            fi
        done

        log_info "Extension installation summary: $installed_count succeeded, $failed_count failed"
    else
        log_info "No extensions configured (VSCODE_EXTENSIONS not set)"
    fi

    # 创建 extensions.json（推荐扩展，如果配置了仓库）
    if [ -n "${REPO_NAME:-}" ]; then
        local repo_dir="${WORKSPACE_DIR:-/workspace}/$REPO_NAME"
        local vscode_dir="$repo_dir/.vscode"

        if [ -d "$repo_dir" ] && [ ! -f "$vscode_dir/extensions.json" ]; then
            mkdir -p "$vscode_dir"

            if [ -n "${VSCODE_EXTENSIONS:-}" ]; then
                # 转换为 JSON 数组
                local extensions_json=$(echo "$VSCODE_EXTENSIONS" | \
                    sed 's/,/","/g' | \
                    sed 's/^/["/' | \
                    sed 's/$/"]/')

                cat > "$vscode_dir/extensions.json" <<EOF
{
    "recommendations": $extensions_json
}
EOF
                log_info "Created .vscode/extensions.json with recommendations"
            fi
        fi
    fi

    log_info "VSCode configuration completed"
}

# 如果直接执行脚本，运行函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    configure_vscode
fi
