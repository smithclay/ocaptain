#!/usr/bin/env bash
# ==============================================================================
# Unit test runner for ocaptain
# ==============================================================================
#
# Runs all BATS unit tests in tests/unit/
#
# Usage:
#   ./tests/run_unit.sh           # Run all unit tests
#   ./tests/run_unit.sh -v        # Verbose output
#   ./tests/run_unit.sh <file>    # Run specific test file
#
# Prerequisites:
#   - bats-core (install via: brew install bats-core)
#   - jq (for JSON function tests)
#
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$SCRIPT_DIR/unit"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check for bats
check_bats() {
  if command -v bats >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${RED}Error: bats-core not found${NC}"
  echo ""
  echo "Install bats-core to run unit tests:"
  echo ""
  echo "  macOS:   brew install bats-core"
  echo "  Linux:   apt install bats (or see https://github.com/bats-core/bats-core)"
  echo ""
  exit 1
}

# Check for jq (required by tests)
check_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Error: jq not found${NC}"
    echo ""
    echo "Install jq to run unit tests:"
    echo ""
    echo "  macOS:   brew install jq"
    echo "  Linux:   apt install jq"
    echo ""
    exit 1
  fi
}

main() {
  check_bats
  check_jq

  echo -e "${CYAN}Running ocaptain unit tests...${NC}"
  echo ""

  # Collect args
  local bats_args=()
  local test_files=()

  for arg in "$@"; do
    case "$arg" in
      -v|--verbose)
        bats_args+=("--verbose-run")
        ;;
      -t|--tap)
        bats_args+=("--tap")
        ;;
      *.bats)
        test_files+=("$arg")
        ;;
      *)
        bats_args+=("$arg")
        ;;
    esac
  done

  # If no test files specified, run all
  if [ ${#test_files[@]} -eq 0 ]; then
    test_files=("$UNIT_DIR"/*.bats)
  fi

  # Run bats (handle empty bats_args array safely)
  if [ ${#bats_args[@]} -eq 0 ]; then
    if bats "${test_files[@]}"; then
      echo ""
      echo -e "${GREEN}All unit tests passed!${NC}"
    else
      echo ""
      echo -e "${RED}Unit tests failed${NC}"
      exit 1
    fi
  else
    if bats "${bats_args[@]}" "${test_files[@]}"; then
      echo ""
      echo -e "${GREEN}All unit tests passed!${NC}"
    else
      echo ""
      echo -e "${RED}Unit tests failed${NC}"
      exit 1
    fi
  fi
}

main "$@"
