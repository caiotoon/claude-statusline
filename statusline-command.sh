#!/bin/bash

# ANSI color codes
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
ORANGE='\033[38;5;208m'
RESET='\033[0m'

# Read JSON input from stdin and extract all values in a single jq call
eval "$(jq -r '
    @sh "cwd=\(.workspace.current_dir)",
    @sh "model=\(.model.display_name)",
    @sh "used_pct=\(.context_window.used_percentage // "")",
    @sh "total_input=\(.context_window.total_input_tokens // "")",
    @sh "total_output=\(.context_window.total_output_tokens // "")",
    @sh "context_size=\(.context_window.context_window_size // "")"
' < /dev/stdin)"

# Replace home directory with ~
display_path="${cwd/#$HOME/~}"

# Change to the working directory
cd "$cwd" 2>/dev/null || cwd="$HOME"

# Initialize output with current directory first
output="${BLUE} ${display_path}${RESET}"

# Git information (if in a git repository)
if git rev-parse --git-dir > /dev/null 2>&1; then
    # Get current branch name
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)

    # Get git status with --no-optional-locks to avoid locking issues
    git_status=$(git --no-optional-locks status --porcelain 2>/dev/null)

    # Count modified, staged, and untracked files
    staged=0
    modified=0
    untracked=0
    if [ -n "$git_status" ]; then
        staged=$(echo "$git_status" | grep -c "^[AMDRC]" 2>/dev/null || true)
        modified=$(echo "$git_status" | grep -c "^.[MD]" 2>/dev/null || true)
        untracked=$(echo "$git_status" | grep -c "^??" 2>/dev/null || true)
    fi
    staged=${staged:-0}
    modified=${modified:-0}
    untracked=${untracked:-0}

    # Check for ahead/behind commits
    ahead=0
    behind=0
    if ahead_behind=$(git --no-optional-locks rev-list --left-right --count HEAD...@{u} 2>/dev/null); then
        ahead=$(echo "$ahead_behind" | awk '{print $1}' | tr -d '[:space:]')
        behind=$(echo "$ahead_behind" | awk '{print $2}' | tr -d '[:space:]')
        [ -z "$ahead" ] && ahead=0
        [ -z "$behind" ] && behind=0
    fi

    # Build git section
    output="${output} │ ${CYAN} ${branch}${RESET}"

    # Add status indicators with colors
    if [ "$staged" -gt 0 ]; then
        output="${output} ${GREEN}✚${staged}${RESET}"
    fi
    if [ "$modified" -gt 0 ]; then
        output="${output} ${YELLOW}●${modified}${RESET}"
    fi
    if [ "$untracked" -gt 0 ]; then
        output="${output} ${RED}…${untracked}${RESET}"
    fi
    if [ "$ahead" -gt 0 ]; then
        output="${output} ${CYAN}⬆${ahead}${RESET}"
    fi
    if [ "$behind" -gt 0 ]; then
        output="${output} ${MAGENTA}⬇${behind}${RESET}"
    fi
fi

# Add model info
output="${output} │ ${MAGENTA}󰚩 ${model}${RESET}"

# Add context with tokens and percentage
if [ -n "$used_pct" ]; then
    used_int=${used_pct%.*}
    if [ "$used_int" -le 60 ]; then
        ctx_color=$GREEN
    elif [ "$used_int" -le 80 ]; then
        ctx_color=$ORANGE
    else
        ctx_color=$RED
    fi

    # Format token count (k for thousands)
    if [ -n "$total_input" ] && [ "$total_input" != "null" ] && [ -n "$context_size" ] && [ "$context_size" != "null" ]; then
        total_tokens=$((total_input + total_output))
        if [ "$total_tokens" -ge 1000 ]; then
            tokens_display="$((total_tokens / 1000))k"
        else
            tokens_display="${total_tokens}"
        fi
        if [ "$context_size" -ge 1000 ]; then
            context_display="$((context_size / 1000))k"
        else
            context_display="${context_size}"
        fi
        output="${output} │ ${ctx_color}󰧑 ${tokens_display}/${context_display} (${used_pct}%)${RESET}"
    else
        output="${output} │ ${ctx_color}󰧑 ${used_pct}%${RESET}"
    fi
fi

printf "%b" "$output"
