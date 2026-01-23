#!/usr/bin/env bash
# Integration test runner for ocaptain
#
# Usage:
#   ./tests/run_integration.sh                    # Run messaging test (requires existing fleet)
#   ./tests/run_integration.sh --setup            # Create fleet, then run messaging test
#   ./tests/run_integration.sh --lifecycle        # Run full lifecycle test (creates/destroys fleet)
#   ./tests/run_integration.sh --all              # Run all integration tests
#
# Prerequisites:
#   - SSH access to exe.dev
#   - GH_TOKEN environment variable (for --setup, --lifecycle, --all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if present
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/.env"
  set +a
fi

export INIT_PATH="$PROJECT_ROOT/cloudinit/init.sh"
export DOTFILES_PATH="$PROJECT_ROOT/dotfiles"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --setup            Create a minimal fleet, then run messaging test
  --lifecycle        Run full lifecycle test (creates and destroys fleet)
  --all              Run all integration tests (lifecycle first, then messaging)
  -h, --help         Show this help message

By default, runs messaging test only (requires existing fleet).
EOF
}

setup_fleet() {
  echo -e "${CYAN}Setting up fleet...${NC}"

  [[ -n "${GH_TOKEN:-}" ]] || { echo "GH_TOKEN required for setup"; exit 1; }

  # Clean existing
  if [[ -f "$HOME/.ocaptain/config.json" ]]; then
    echo "Cleaning existing fleet..."
    "$PROJECT_ROOT/ocaptain" fleet sink --force --scuttle 2>/dev/null || true
    rm -rf "$HOME/.ocaptain"
  fi

  # Create flagship
  echo "Creating flagship..."
  "$PROJECT_ROOT/ocaptain" init

  # Create one ship
  echo "Creating ship..."
  "$PROJECT_ROOT/ocaptain" ship create test-ship

  echo -e "${GREEN}Fleet ready${NC}"
  "$PROJECT_ROOT/ocaptain" fleet status
}

run_messaging_test() {
  echo ""
  echo -e "${CYAN}Running messaging test...${NC}"
  echo ""

  if bash "$SCRIPT_DIR/integration/test_messaging.sh"; then
    echo -e "${GREEN}Messaging test passed!${NC}"
    return 0
  else
    echo -e "${RED}Messaging test failed${NC}"
    return 1
  fi
}

run_lifecycle_test() {
  echo ""
  echo -e "${CYAN}Running fleet lifecycle test...${NC}"
  echo ""

  [[ -n "${GH_TOKEN:-}" ]] || { echo -e "${RED}GH_TOKEN required for lifecycle test${NC}"; exit 1; }

  if bash "$SCRIPT_DIR/integration/test_fleet_lifecycle.sh"; then
    echo -e "${GREEN}Lifecycle test passed!${NC}"
    return 0
  else
    echo -e "${RED}Lifecycle test failed${NC}"
    return 1
  fi
}

check_exe_dev() {
  echo -e "${CYAN}Checking exe.dev access...${NC}"
  if ssh exe.dev whoami >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
    return 0
  else
    echo -e "${RED}Cannot connect to exe.dev${NC}"
    return 1
  fi
}

main() {
  local run_lifecycle=false
  local run_messaging=false
  local do_setup=false

  # Parse arguments
  case "${1:-}" in
    --setup)
      do_setup=true
      run_messaging=true
      ;;
    --lifecycle)
      run_lifecycle=true
      ;;
    --all)
      run_lifecycle=true
      run_messaging=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    "")
      run_messaging=true
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      usage
      exit 1
      ;;
  esac

  check_exe_dev || exit 1

  local failed=false

  # Run lifecycle test first (it creates/destroys its own fleet)
  if [[ "$run_lifecycle" == "true" ]]; then
    if ! run_lifecycle_test; then
      failed=true
    fi
  fi

  # Setup fleet if requested
  if [[ "$do_setup" == "true" ]]; then
    setup_fleet
  fi

  # Run messaging test (requires existing fleet)
  if [[ "$run_messaging" == "true" ]]; then
    if ! run_messaging_test; then
      failed=true
    fi
  fi

  echo ""
  if [[ "$failed" == "true" ]]; then
    echo -e "${RED}Some integration tests failed${NC}"
    exit 1
  else
    echo -e "${GREEN}All integration tests passed!${NC}"
  fi
}

main "$@"
