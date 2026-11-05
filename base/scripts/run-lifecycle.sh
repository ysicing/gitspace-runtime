#!/bin/bash
set -euo pipefail

run_lifecycle_command() {
    local command_json="$1"
    local command_type
    command_type=$(printf '%s' "$command_json" | jq -er 'type') || return 1

    case "$command_type" in
        string)
            /bin/sh -c "$(printf '%s' "$command_json" | jq -r '.')"
            ;;
        array)
            local quoted_arguments
            quoted_arguments=$(printf '%s' "$command_json" | jq -er '
                if all(.[]; type == "string") then @sh else error("arguments must be strings") end
            ') || return 1
            if [ -n "$quoted_arguments" ]; then
                eval "set -- $quoted_arguments"
                "$@"
            fi
            ;;
        object)
            local encoded_command
            local process_ids=()
            while IFS= read -r encoded_command; do
                run_lifecycle_command "$(printf '%s' "$encoded_command" | base64 --decode)" &
                process_ids+=("$!")
            done < <(printf '%s' "$command_json" | jq -r '.[] | tojson | @base64')
            local result=0
            local process_id
            for process_id in "${process_ids[@]}"; do
                wait "$process_id" || result=1
            done
            return "$result"
            ;;
        *)
            printf '[ERROR] Unsupported lifecycle command type: %s\n' "$command_type" >&2
            return 1
            ;;
    esac
}

run_gitspace_lifecycle() (
    cd "$REPO_DIR" || return 1
    if [ -n "${GITSPACE_POST_CREATE_COMMAND:-}" ]; then
        local marker_dir="${TMPDIR:-/tmp}/gitspace-lifecycle-$UID"
        local repository_key create_marker
        if [ -L "$marker_dir" ] || { [ -e "$marker_dir" ] && [ ! -O "$marker_dir" ]; }; then
            printf '[ERROR] Unsafe lifecycle marker directory\n' >&2
            return 1
        fi
        mkdir -p "$marker_dir" || return 1
        chmod 700 "$marker_dir" || return 1
        repository_key=$(pwd -P | git hash-object --stdin) || return 1
        create_marker="$marker_dir/$repository_key"

        # 标记随容器临时层失效，重建后重新安装系统依赖；同一容器只执行一次。
        if [ ! -f "$create_marker" ]; then
            run_lifecycle_command "$GITSPACE_POST_CREATE_COMMAND" || return 1
            touch "$create_marker" || return 1
        fi
    fi
    if [ -n "${GITSPACE_POST_START_COMMAND:-}" ]; then
        run_lifecycle_command "$GITSPACE_POST_START_COMMAND" || return 1
    fi
)
