#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

scripts=(
    base/scripts/clone-repository.sh
    base/scripts/setup-ssh.sh
    base/scripts/run-lifecycle.sh
    vscode/gitspace-run.sh
    vscode-web/gitspace-run.sh
    vscode-web/gitspace-init.sh
    cursor/gitspace-run.sh
    jetbrains/gitspace-run.sh
    jetbrains/scripts/install-plugins.sh
)
for script in "${scripts[@]}"; do
    bash -n "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning -e SC1090,SC1091 "${scripts[@]}"
fi
node --check vscode-web/scripts/prepare-config.cjs
python3 -B -m unittest discover -s tests -v
