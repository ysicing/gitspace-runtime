# === my_clean_robby.zsh-theme ===
# 简洁、对齐、颜色协调的 robbyrussell 风格增强版
# 特点：时间变色、主机名、路径、Git 状态（不显示执行结果符号）

# 颜色定义
local RED="%{$fg[red]%}"
local GREEN="%{$fg[green]%}"
local YELLOW="%{$fg[yellow]%}"
local BLUE="%{$fg[blue]%}"
local BOLD_BLUE="%{$fg_bold[blue]%}"
local BOLD_GREEN="%{$fg_bold[green]%}"
local BOLD_RED="%{$fg_bold[red]%}"
local CYAN="%{$fg[cyan]%}"
local RESET="%{$reset_color%}"

# 主机名与时间：时间颜色根据命令结果自动切换
local hostname="${BOLD_GREEN}%m${RESET}"
local time="%(?.${YELLOW}.${RED})%T${RESET}"

# Git 提示配置（与 oh-my-zsh git 插件配合）
ZSH_THEME_GIT_PROMPT_PREFIX="${BOLD_BLUE}git:(${RED}"
ZSH_THEME_GIT_PROMPT_SUFFIX="${RESET} "
ZSH_THEME_GIT_PROMPT_DIRTY="${BLUE}) ${YELLOW}✗${RESET}"
ZSH_THEME_GIT_PROMPT_CLEAN="${BLUE})${RESET}"

# Prompt 样式（保持原版 robbyrussell 风格）
PROMPT='${time} ${hostname} %(?:${BOLD_GREEN}➜ :${BOLD_RED}➜ ) ${CYAN}%c${RESET} $(git_prompt_info) '

RPROMPT=''
