#!/bin/bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

toon () {
  case "$(uname -s)" in
    Darwin) echo -n "" ;;   # macOS
    Linux)  echo -n "🐧" ;;  # Linux
    *)      echo -n "◇" ;;
  esac
}

# Calculate context window usage from transcript file
# Read last non-sidechain entry with usage data (like @this-dot/claude-code-context-status-line)
context_info=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # Get the last line with message.usage.input_tokens that isn't a sidechain
    # Read file backwards, find first valid entry
    total_tokens=$(tac "$transcript_path" 2>/dev/null | while read -r line; do
        # Skip sidechain entries
        is_sidechain=$(echo "$line" | jq -r '.isSidechain // false' 2>/dev/null)
        [ "$is_sidechain" = "true" ] && continue

        # Get input_tokens from message.usage
        input_tokens=$(echo "$line" | jq -r '.message.usage.input_tokens // empty' 2>/dev/null)
        [ -z "$input_tokens" ] && continue

        # Get cache tokens
        cache_read=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)
        cache_create=$(echo "$line" | jq -r '.message.usage.cache_creation_input_tokens // 0' 2>/dev/null)

        # Output total and exit loop
        echo $(( input_tokens + cache_read + cache_create ))
        break
    done)

    context_limit=200000
    if [ -n "$total_tokens" ] && [ "$total_tokens" -gt 0 ]; then
        context_remaining=$(( 100 - (total_tokens * 100 / context_limit) ))
        [ "$context_remaining" -lt 0 ] && context_remaining=0

        # Color based on remaining context (green > 50%, yellow 20-50%, red < 20%)
        if [ "$context_remaining" -gt 50 ]; then
            context_color="\033[32m"  # green
        elif [ "$context_remaining" -gt 20 ]; then
            context_color="\033[33m"  # yellow
        else
            context_color="\033[31m"  # red
        fi
        context_info=" $(toon) ${context_color}${context_remaining}%%\033[0m"
    fi
fi

# Get git branch if in a repo
git_info=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        # Check for changes
        if ! git -C "$cwd" diff --quiet 2>/dev/null; then
            git_info=" [${branch}*]"
        elif ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
            git_info=" [${branch}+]"
        else
            git_info=" [${branch}]"
        fi
    fi
fi

# Print status line with magenta color for directory (matching apple theme)
printf "\033[35m%s\033[0m%s${context_info}" "$(basename "$cwd")" "$git_info"
