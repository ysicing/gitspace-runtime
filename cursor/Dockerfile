# Copyright (c) 2025-2025 All rights reserved.
#
# The original source code is licensed under the Apache License 2.0.
# New features or modifications to this source code are licensed under the
# Affero General Public License 3.0 (AGPL 3.0).
#
# You may review the terms of both licenses in the LICENSE file.

# Gitspace Cursor/Windsurf 专用镜像
# 基于 VSCode 镜像（Cursor 和 Windsurf 基于 VSCode）

FROM ghcr.io/ysicing/gitspace-runtime:vscode-latest

LABEL maintainer="Gitness Team"
LABEL description="Gitspace Cursor/Windsurf image"

USER root

# Cursor/Windsurf 额外依赖（如果需要）
# 目前与 VSCode 依赖相同，未来可能需要额外工具

# 复制 Cursor 专用脚本
COPY cursor/scripts/*.sh /usr/local/gitspace/scripts/cursor/
RUN chmod +x /usr/local/gitspace/scripts/cursor/*.sh

# 复制 Cursor 初始化脚本
COPY cursor/init-cursor.sh /usr/local/bin/gitspace-init.sh
RUN chmod +x /usr/local/bin/gitspace-init.sh

# 切换到非 root 用户
USER vscode

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD [ "which", "git" ]

CMD ["sleep", "infinity"]
