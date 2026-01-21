alias gs="git status"
alias gb="git branch"
alias ga="git add"
alias gc="git commit"
alias gp="git push"

if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    alias timeout="gtimeout"
  fi
fi

alias vi="nvim"
# ls / ll via eza if available
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza --icons --long --group-directories-first'
fi

# cat via bat if available
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --style=plain --color=always'
fi

alias venv-activate="source .venv/bin/activate"

if [[ "$OSTYPE" == darwin* ]]; then
    alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

# allow dangerous claude in exe.dev
if [[ "$USER" == "exedev" ]]; then
  alias claude='claude --dangerously-skip-permissions'
fi
