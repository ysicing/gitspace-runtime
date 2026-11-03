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
    local create_marker
    create_marker=$(git rev-parse --git-path gitspace-post-create-complete) || return 1

    # 仅成功完成后记录，失败重启仍可重试；标记随仓库而非整个 HOME 保存。
    if [ -n "${GITSPACE_POST_CREATE_COMMAND:-}" ] && [ ! -f "$create_marker" ]; then
        run_lifecycle_command "$GITSPACE_POST_CREATE_COMMAND" || return 1
        touch "$create_marker" || return 1
    fi
    if [ -n "${GITSPACE_POST_START_COMMAND:-}" ]; then
        run_lifecycle_command "$GITSPACE_POST_START_COMMAND" || return 1
    fi
)
