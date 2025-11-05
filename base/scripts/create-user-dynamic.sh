#!/bin/bash
# 动态创建或更新用户
# 支持: 创建新用户, 更新 UID/GID, 设置 HOME 目录权限

set -euo pipefail

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

create_or_update_user() {
    local username="${1:-vscode}"
    local uid="${2:-1000}"
    local gid="${3:-1000}"
    local home_dir="${4:-/home/$username}"

    log_info "=========================================="
    log_info "Configuring user: $username (UID: $uid, GID: $gid)"
    log_info "HOME directory: $home_dir"
    log_info "=========================================="

    # 特殊处理: root 用户不需要创建
    if [ "$username" = "root" ]; then
        log_info "User is root, skipping user creation"
        ensure_home_directory "$home_dir" "$uid" "$gid"
        log_success "Root user configuration completed"
        return 0
    fi

    # 检查用户是否存在
    if id "$username" >/dev/null 2>&1; then
        handle_existing_user "$username" "$uid" "$gid" "$home_dir"
    else
        create_new_user "$username" "$uid" "$gid" "$home_dir"
    fi

    # 确保 HOME 目录权限正确
    ensure_home_directory "$home_dir" "$uid" "$gid"

    log_success "User configuration completed"
}

# 处理已存在的用户
handle_existing_user() {
    local username="$1"
    local uid="$2"
    local gid="$3"
    local home_dir="$4"

    local existing_uid
    existing_uid=$(id -u "$username")
    local existing_gid
    existing_gid=$(id -g "$username")

    if [ "$existing_uid" = "$uid" ] && [ "$existing_gid" = "$gid" ]; then
        log_info "User $username already exists with correct UID/GID"
    else
        log_info "User $username exists but with different UID/GID"
        log_info "  Existing: UID=$existing_uid, GID=$existing_gid"
        log_info "  Expected: UID=$uid, GID=$gid"

        # 检查目标 UID/GID 是否已被占用
        if id "$uid" >/dev/null 2>&1 && [ "$(id -un "$uid")" != "$username" ]; then
            log_error "UID $uid is already taken by another user: $(id -un "$uid")"
            log_error "Cannot update user UID/GID"
            return 1
        fi

        log_info "Updating user UID/GID..."

        # 更新 UID/GID (需要 root 权限)
        sudo usermod -u "$uid" "$username" 2>/dev/null || {
            log_error "Failed to update UID for $username"
            return 1
        }

        # 更新组 GID
        local group_name
        group_name=$(id -gn "$username")
        sudo groupmod -g "$gid" "$group_name" 2>/dev/null || {
            log_error "Failed to update GID for group $group_name"
            return 1
        }

        log_success "Updated UID/GID for $username"

        # 更新文件所有权
        log_info "Updating file ownership (this may take a while)..."
        sudo find "$home_dir" -user "$existing_uid" -exec chown "$uid" {} + 2>/dev/null || true
        sudo find "$home_dir" -group "$existing_gid" -exec chgrp "$gid" {} + 2>/dev/null || true
    fi
}

# 创建新用户
create_new_user() {
    local username="$1"
    local uid="$2"
    local gid="$3"
    local home_dir="$4"

    log_info "User $username does not exist, creating..."

    # 检查 UID 是否已被占用
    if id "$uid" >/dev/null 2>&1; then
        log_error "UID $uid is already taken by: $(id -un "$uid")"
        return 1
    fi

    # 检查组是否存在
    if ! getent group "$username" >/dev/null 2>&1; then
        log_info "Creating group: $username (GID: $gid)"
        sudo groupadd -g "$gid" "$username" 2>/dev/null || {
            # 如果 GID 已被占用,使用系统分配的 GID
            log_info "GID $gid is taken, using system-assigned GID"
            sudo groupadd "$username"
            gid=$(getent group "$username" | cut -d: -f3)
        }
    fi

    # 创建用户
    log_info "Creating user: $username (UID: $uid, GID: $gid)"
    sudo useradd -m -u "$uid" -g "$gid" -s /bin/bash -d "$home_dir" "$username" || {
        log_error "Failed to create user $username"
        return 1
    }

    # 添加 sudo 权限
    log_info "Granting sudo privileges to $username"
    echo "$username ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$username > /dev/null
    sudo chmod 0440 /etc/sudoers.d/$username

    log_success "User $username created successfully"
}

# 确保 HOME 目录存在且权限正确
ensure_home_directory() {
    local home_dir="$1"
    local uid="$2"
    local gid="$3"

    # 创建 HOME 目录
    if [ ! -d "$home_dir" ]; then
        log_info "Creating HOME directory: $home_dir"
        sudo mkdir -p "$home_dir"
    fi

    # 设置权限
    log_info "Setting permissions on HOME directory..."
    sudo chown -R "$uid:$gid" "$home_dir" 2>/dev/null || {
        log_error "Failed to set permissions on $home_dir"
        return 1
    }

    # 创建常用配置目录
    for dir in .config .local .cache .ssh; do
        local target_dir="$home_dir/$dir"
        if [ ! -d "$target_dir" ]; then
            sudo mkdir -p "$target_dir"
            sudo chown "$uid:$gid" "$target_dir"
        fi
    done

    # 设置 .ssh 目录权限 (SSH 要求严格权限)
    if [ -d "$home_dir/.ssh" ]; then
        sudo chmod 700 "$home_dir/.ssh"
    fi

    log_info "HOME directory configured"
}

# 如果直接执行
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
    create_or_update_user "$@"
fi

