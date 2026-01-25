#!/usr/bin/env bash
set -euo pipefail

# Log to cloud-init location (same as AWS EC2)
LOG_FILE="/var/log/cloud-init-output.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="$HOME/.ocaptain/init.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Redirect all output to log file (quiet mode)
exec >> "$LOG_FILE" 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED: $*"; exit 1; }

log "Starting ocaptain init..."

TARGET_REPO="${TARGET_REPO:-}"
DOTFILES_PATH="${DOTFILES_PATH:-}"  # Local dotfiles path (highest priority)
DOTFILES_URL="${DOTFILES_URL:-https://github.com/smithclay/ocaptain}"  # Remote dotfiles repo

# GH_TOKEN only required if cloning a repo
if [[ -n "$TARGET_REPO" && -z "${GH_TOKEN:-}" ]]; then
  die "GH_TOKEN env var is required when TARGET_REPO is set"
fi

export DEBIAN_FRONTEND=noninteractive

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Portable base64 decode (works on both Linux and macOS)
base64_decode() {
  openssl base64 -d -A
}

log "Installing GitHub CLI (gh) if missing..."
if ! need_cmd gh; then
  die "expected gh cli to be installed on base image"
fi

# Only authenticate gh if we have a token
if [[ -n "${GH_TOKEN:-}" ]]; then
  log "Persisting gh credentials for future sessions..."
  _token="$GH_TOKEN"
  # Must unset GH_TOKEN before gh auth login, otherwise gh uses env var instead of storing credentials
  unset GH_TOKEN
  printf '%s\n' "$_token" | gh auth login --hostname github.com --with-token >/dev/null 2>&1
  unset _token

  log "Configuring git via gh..."
  gh auth setup-git --hostname github.com >/dev/null 2>&1
else
  # Clear any stale GH_TOKEN from environment
  unset GH_TOKEN 2>/dev/null || true
fi

if [[ -n "$TARGET_REPO" ]]; then
  log "Verifying token can access repo: $TARGET_REPO"
  gh repo view "$TARGET_REPO" --json nameWithOwner >/dev/null

  REPO_NAME="$(basename "$TARGET_REPO")"
  DEST="$HOME/$REPO_NAME"

  if [[ -d "$DEST/.git" ]]; then
    log "Repo already exists at $DEST — fetching latest"
    (cd "$DEST" && git fetch --all --prune)
  else
    log "Cloning $TARGET_REPO into $DEST"
    gh repo clone "$TARGET_REPO" "$DEST"
  fi
fi


# Configure Claude Code to skip onboarding
log "Configuring Claude Code..."
echo '{"hasCompletedOnboarding":true}' > ~/.claude.json

log "Init complete. Repo: ${TARGET_REPO:-none}"
