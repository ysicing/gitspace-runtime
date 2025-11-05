#!/bin/bash
# 从 devcontainer.json 检测用户配置
# 返回: CONTAINER_USER, REMOTE_USER, USER_UID, USER_GID, HOME_DIR

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

detect_devcontainer_user() {
    local repo_dir="${1:-/workspaces}"
    local devcontainer_file="$repo_dir/.devcontainer/devcontainer.json"

    # 默认值 (可被环境变量覆盖)
    local container_user="${CONTAINER_USER:-vscode}"
    local remote_user="${REMOTE_USER:-}"
    local user_uid="${USER_UID:-1000}"
    local user_gid="${USER_GID:-1000}"

    # 如果 devcontainer.json 存在,读取配置
    if [ -f "$devcontainer_file" ]; then
        log_info "Found devcontainer.json, parsing user configuration..."

        # 解析 containerUser
        local container_user_from_file
        container_user_from_file=$(jq -r '.containerUser // empty' "$devcontainer_file" 2>/dev/null || echo "")
        if [ -n "$container_user_from_file" ]; then
            container_user="$container_user_from_file"
            log_info "Using containerUser from devcontainer.json: $container_user"
        fi

        # 解析 remoteUser
        local remote_user_from_file
        remote_user_from_file=$(jq -r '.remoteUser // empty' "$devcontainer_file" 2>/dev/null || echo "")
        if [ -n "$remote_user_from_file" ]; then
            remote_user="$remote_user_from_file"
            log_info "Using remoteUser from devcontainer.json: $remote_user"
        fi
    else
        log_info "No devcontainer.json found, using defaults"
    fi

    # 如果 remoteUser 未设置,使用 containerUser
    if [ -z "$remote_user" ]; then
        remote_user="$container_user"
    fi

    # 解析用户字符串获取 UID/GID
    parse_user_string "$container_user"

    # 计算 HOME 目录
    local home_dir
    if [ "$remote_user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$remote_user"
    fi

    # 输出结果 (可以被 source)
    echo "export CONTAINER_USER='$container_user'"
    echo "export REMOTE_USER='$remote_user'"
    echo "export USER_UID='$user_uid'"
    echo "export USER_GID='$user_gid'"
    echo "export HOME_DIR='$home_dir'"

    log_info "User detection completed:"
    log_info "  CONTAINER_USER=$container_user"
    log_info "  REMOTE_USER=$remote_user"
    log_info "  USER_UID=$user_uid"
    log_info "  USER_GID=$user_gid"
    log_info "  HOME_DIR=$home_dir"
}

# 解析用户字符串 (username, uid, username:gid, uid:gid)
parse_user_string() {
    local user_str="$1"

    # 检查是否包含 :
    if [[ "$user_str" == *:* ]]; then
        # 格式: username:groupname 或 uid:gid
        IFS=':' read -r user_part group_part <<< "$user_str"

        # 检查 user_part 是否是纯数字
        if [[ "$user_part" =~ ^[0-9]+$ ]]; then
            user_uid="$user_part"
        else
            # 从系统查找用户 UID (可能不存在)
            if id "$user_part" >/dev/null 2>&1; then
                user_uid=$(id -u "$user_part")
            else
                # 用户不存在,使用默认值
                user_uid="${USER_UID:-1000}"
            fi
        fi

        # 检查 group_part 是否是纯数字
        if [[ "$group_part" =~ ^[0-9]+$ ]]; then
            user_gid="$group_part"
        else
            # 从系统查找组 GID (可能不存在)
            if getent group "$group_part" >/dev/null 2>&1; then
                user_gid=$(getent group "$group_part" | cut -d: -f3)
            else
                # 组不存在,使用默认值
                user_gid="${USER_GID:-1000}"
            fi
        fi
    else
        # 格式: username 或 uid
        if [[ "$user_str" =~ ^[0-9]+$ ]]; then
            # 纯数字,直接作为 UID
            user_uid="$user_str"
            user_gid="$user_str"
        else
            # 用户名,尝试从系统查找
            if id "$user_str" >/dev/null 2>&1; then
                user_uid=$(id -u "$user_str")
                user_gid=$(id -g "$user_str")
            else
                # 用户不存在,使用默认值
                user_uid="${USER_UID:-1000}"
                user_gid="${USER_GID:-1000}"
            fi
        fi
    fi
}

# 如果直接执行
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
    detect_devcontainer_user "$@"
fi

