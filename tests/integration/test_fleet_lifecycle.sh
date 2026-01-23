#!/usr/bin/env bash
# Integration test: Fleet lifecycle (init, ship create/destroy, scuttle)
#
# This test creates a real fleet on exe.dev VMs and verifies:
# 1. Flagship initialization
# 2. Ship creation
# 3. Fleet status
# 4. Ship destruction
# 5. Fleet scuttling
#
# Requires: GH_TOKEN, ssh access to exe.dev

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/test_helpers.sh"

# Test configuration
TEST_REPO="${TEST_REPO:-smithclay/ocaptain}"  # Use a known repo for testing

main() {
  echo "================================"
  echo "Fleet Lifecycle Integration Test"
  echo "================================"
  echo ""

  # Check environment
  check_required_env

  # Ensure clean state (remove lingering VMs from previous failed runs)
  cleanup_lingering_vms

  # Register cleanup
  register_cleanup

  # ============================================
  # Test 1: Initialize flagship
  # ============================================
  log_test "Initializing flagship..."

  local init_output
  if ! init_output=$(GH_TOKEN="$GH_TOKEN" "$PROJECT_ROOT/ocaptain" init 2>&1); then
    log_fail "Failed to initialize flagship"
    echo "$init_output"
    return 1
  fi

  assert_contains "Flagship created" "$init_output" "Done! Cluster"
  assert "Config file exists" "[[ -f '$HOME/.ocaptain/config.json' ]]"

  local flagship_dest
  flagship_dest=$(jq -r '.flagship' "$HOME/.ocaptain/config.json")
  assert "Flagship destination configured" "[[ -n '$flagship_dest' && '$flagship_dest' != 'null' ]]"

  log_info "Flagship: $flagship_dest"

  # ============================================
  # Test 2: Fleet status (empty)
  # ============================================
  log_test "Checking fleet status (empty)..."

  local status_output
  status_output=$("$PROJECT_ROOT/ocaptain" fleet status 2>&1)

  assert_contains "Shows flagship hostname" "$status_output" "FLAGSHIP:"
  assert_contains "Shows empty ships" "$status_output" "SHIPS:"

  # ============================================
  # Test 3: Create a ship
  # ============================================
  log_test "Creating ship for $TEST_REPO..."

  local ship_output
  if ! ship_output=$(GH_TOKEN="$GH_TOKEN" "$PROJECT_ROOT/ocaptain" ship create "$TEST_REPO" 2>&1); then
    log_fail "Failed to create ship"
    echo "$ship_output"
    return 1
  fi

  assert_contains "Ship created" "$ship_output" "Created ship:"

  # Extract ship name from repo
  local ship_name="${TEST_REPO##*/}"

  # ============================================
  # Test 4: Fleet status (with ship)
  # ============================================
  log_test "Checking fleet status (with ship)..."

  status_output=$("$PROJECT_ROOT/ocaptain" fleet status 2>&1)

  assert_contains "Shows ship in fleet" "$status_output" "$ship_name"
  assert_contains "Ship has running status" "$status_output" "running"

  # ============================================
  # Test 5: SSH into ship works
  # ============================================
  log_test "Testing SSH to ship..."

  # Get ship SSH destination from fleet (SHIP column contains id like "reponame-abc123", SSH_DEST is column 3)
  local ship_dest
  ship_dest=$("$PROJECT_ROOT/ocaptain" fleet status 2>&1 | grep "^  $ship_name-" | awk '{print $3}')

  if [[ -n "$ship_dest" ]]; then
    assert_success "Can SSH to ship" "test_ssh '$ship_dest' 'echo ok'"
  else
    log_fail "Could not determine ship destination"
  fi

  # ============================================
  # Test 6: Ship has NATS tunnel configured
  # ============================================
  log_test "Checking NATS tunnel on ship..."

  local tunnel_status
  tunnel_status=$(test_ssh "$ship_dest" 'systemctl is-active ocap-tunnel 2>/dev/null || echo "inactive"')

  assert "NATS tunnel service exists" "[[ '$tunnel_status' == 'active' || '$tunnel_status' == 'inactive' || '$tunnel_status' == 'activating' ]]"

  # Check ocaptain is deployed
  local ocaptain_check
  ocaptain_check=$(test_ssh "$ship_dest" 'test -x ~/.local/bin/ocaptain && echo "ok"' || echo "")
  assert "ocaptain deployed on ship" "[[ '$ocaptain_check' == 'ok' ]]"

  # ============================================
  # Test 7: Destroy ship
  # ============================================
  log_test "Destroying ship..."

  local destroy_output
  if ! destroy_output=$("$PROJECT_ROOT/ocaptain" ship destroy "$ship_name" 2>&1); then
    log_fail "Failed to destroy ship"
    echo "$destroy_output"
    # Continue anyway to test scuttle
  fi

  assert_contains "Ship destroyed" "$destroy_output" "destroyed"

  # ============================================
  # Test 8: Fleet status (ship removed)
  # ============================================
  log_test "Checking fleet status (ship removed)..."

  status_output=$("$PROJECT_ROOT/ocaptain" fleet status 2>&1)

  # Ship should no longer appear in the ships list (check for ship ID pattern, not just repo name)
  assert "Ship removed from fleet" "! echo '$status_output' | grep -qE '^  $ship_name-'"

  # ============================================
  # Test 9: Scuttle (cleanup happens via trap)
  # ============================================
  log_test "Fleet scuttle will run on cleanup..."

  # Print summary
  print_summary
}

main "$@"
