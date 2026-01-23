#!/usr/bin/env bash
# ==============================================================================
# Shared BATS test helpers for ocaptain unit tests
# ==============================================================================
#
# This file provides common setup/teardown for isolated testing of pure
# functions. Each test runs with a temporary HOME to avoid touching real
# ~/.ocaptain configuration.
#
# Usage in .bats files:
#   load 'helpers/common'
#
# ==============================================================================

# Get project root (3 levels up from helpers/common.bash)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

# Store original HOME for restoration
_ORIGINAL_HOME="$HOME"

# ==============================================================================
# Setup/Teardown
# ==============================================================================

# Setup runs before each test - creates isolated temp environment
common_setup() {
  # Create temp directory for this test
  TEST_TEMP_DIR="$(mktemp -d)"

  # Override HOME to isolate tests from real config
  export HOME="$TEST_TEMP_DIR"

  # Create required directories
  mkdir -p "$HOME/.ocaptain/ns/default"

  # Source ocaptain to get function definitions
  # (OCAP_SOURCED detection prevents main() from executing)
  source "$PROJECT_ROOT/ocaptain"
}

# Teardown runs after each test - cleans up temp environment
common_teardown() {
  # Restore original HOME
  export HOME="$_ORIGINAL_HOME"

  # Clean up temp directory
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# ==============================================================================
# Mock Helpers
# ==============================================================================

# Create a mock identity file with specified role
# Usage: create_mock_identity "captain"
create_mock_identity() {
  local role="${1:-local}"
  mkdir -p "$HOME/.ocaptain"
  echo "{\"role\": \"$role\"}" > "$HOME/.ocaptain/identity.json"
}

# Create a mock config file with flagship
# Usage: create_mock_config "user@host"
create_mock_config() {
  local flagship="${1:-localhost}"
  mkdir -p "$HOME/.ocaptain"
  echo "{\"flagship\": \"$flagship\"}" > "$HOME/.ocaptain/config.json"
}

# Create a mock ships registry
# Usage: create_mock_ships_registry '{"ship-abc123": {"repo": "owner/repo"}}'
create_mock_ships_registry() {
  local registry_json="${1:-\{\}}"
  local ns_dir="$HOME/.ocaptain/ns/default"
  mkdir -p "$ns_dir"
  printf '%s\n' "$registry_json" > "$ns_dir/ships.json"
}

# Create sample VM JSON for testing pure functions
# Usage: sample_vms_json
sample_vms_json() {
  cat <<'EOF'
[
  {"vm_name": "flagship-ocaptain-abc123", "ssh_dest": "user@flagship.example.com", "status": "running"},
  {"vm_name": "ship-myrepo-def456", "ssh_dest": "user@ship1.example.com", "status": "running"},
  {"vm_name": "ship-myrepo-ghi789", "ssh_dest": "user@ship2.example.com", "status": "running"},
  {"vm_name": "ship-other-jkl012", "ssh_dest": "user@ship3.example.com", "status": "stopped"},
  {"vm_name": "unrelated-vm", "ssh_dest": "user@other.example.com", "status": "running"}
]
EOF
}

# Create sample registry JSON for testing
# Usage: sample_registry_json
sample_registry_json() {
  cat <<'EOF'
{
  "myrepo-def456": {"repo": "owner/myrepo"},
  "myrepo-ghi789": {"repo": "owner/myrepo"},
  "other-jkl012": {"repo": "owner/other"}
}
EOF
}
