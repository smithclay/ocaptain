#!/usr/bin/env bash
# Integration test: NATS Messaging System
#
# Tests the core messaging flow: flagship -> ship -> artifact
#
# Prerequisites:
#   - Fleet must already exist (run ./ocaptain init + ship create first)
#   - Or set CREATE_FLEET=true to create one
#
# Usage:
#   ./tests/integration/test_messaging.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; exit 1; }
info() { echo "INFO: $1"; }

# Check for existing fleet
check_fleet() {
  if [[ ! -f "$HOME/.ocaptain/config.json" ]]; then
    echo "No fleet configured. Run:"
    echo "  ./ocaptain init"
    echo "  ./ocaptain ship create <repo-or-name>"
    exit 1
  fi

  local ship_count
  ship_count=$("$PROJECT_ROOT/ocaptain" fleet status --json 2>&1 | jq '.ships | length')

  if [[ "$ship_count" -lt 1 ]]; then
    echo "Need at least 1 ship. Current fleet:"
    "$PROJECT_ROOT/ocaptain" fleet status
    exit 1
  fi
}

main() {
  echo "=== NATS Messaging Test ==="
  echo ""

  check_fleet

  # Get fleet info (using JSON for reliable parsing)
  local flagship ship_dest ship_id fleet_json
  fleet_json=$("$PROJECT_ROOT/ocaptain" fleet status --json 2>&1)
  flagship=$(echo "$fleet_json" | jq -r '.flagship')
  ship_dest=$(echo "$fleet_json" | jq -r '.ships[0].ssh_dest')
  ship_id=$(echo "$fleet_json" | jq -r '.ships[0].id')

  [[ -n "$flagship" ]] || fail "Could not get flagship"
  [[ -n "$ship_dest" ]] || fail "Could not get ship destination"
  [[ -n "$ship_id" ]] || fail "Could not get ship ID"

  info "Flagship: $flagship"
  info "Ship: $ship_id ($ship_dest)"
  echo ""

  # Accept host keys
  ssh -o StrictHostKeyChecking=accept-new "$flagship" true 2>/dev/null || true
  ssh -o StrictHostKeyChecking=accept-new "$ship_dest" true 2>/dev/null || true

  # Test 1: NATS server running
  echo "Test 1: NATS server on flagship"
  if ssh "$flagship" 'systemctl is-active nats-server' | grep -q active; then
    pass "NATS server is active"
  else
    fail "NATS server not running"
  fi

  # Test 2: NATS tunnel running
  echo "Test 2: NATS tunnel on ship"
  if ssh "$ship_dest" 'systemctl is-active ocap-tunnel' | grep -q active; then
    pass "NATS tunnel is active"
  else
    fail "NATS tunnel not running"
  fi

  # Test 3: End-to-end messaging
  echo "Test 3: End-to-end messaging"

  # Clean artifacts
  ssh "$ship_dest" 'rm -rf ~/.ocaptain/ns/default/artifacts/*' || true

  # Start scheduler
  ssh "$ship_dest" 'pkill -f _scheduler' 2>/dev/null || true
  ssh "$ship_dest" 'nohup ~/.local/bin/ocaptain _scheduler > /tmp/sched.log 2>&1 &'
  sleep 2

  # Send message
  local test_marker
  test_marker="TEST_$(date +%s)"
  info "Sending test marker: $test_marker"
  # shellcheck disable=SC2029  # Intentional client-side expansion
  ssh "$flagship" "\$HOME/.local/bin/ocaptain inbox send captain@$ship_id 'echo $test_marker'" || true

  # Wait for processing
  sleep 3

  # Stop scheduler
  ssh "$ship_dest" 'pkill -f _scheduler' 2>/dev/null || true

  # Check artifact
  local artifact_content
  artifact_content=$(ssh "$ship_dest" 'cat ~/.ocaptain/ns/default/artifacts/*/stdout.txt 2>/dev/null || echo ""')

  if [[ "$artifact_content" == *"$test_marker"* ]]; then
    pass "Message delivered and executed (found: $test_marker)"
  else
    echo "Artifact content: '$artifact_content'"
    echo "Scheduler log:"
    ssh "$ship_dest" 'cat /tmp/sched.log' 2>/dev/null || true
    fail "Message not processed"
  fi

  echo ""
  echo "=== All tests passed ==="
}

main "$@"
