# ocaptain Makefile
# ==================
#
# Usage:
#   make test                 Run unit tests (fast, default)
#   make test-integration     Run messaging test (requires existing fleet)
#   make test-lifecycle       Run lifecycle test (creates/destroys fleet)
#   make test-all             Run all tests (unit + all integration)
#   make setup-fleet          Create a test fleet
#   make clean-fleet          Destroy all VMs and local config
#
# Prerequisites:
#   - Unit tests: bats-core, jq
#   - Integration tests: SSH access to exe.dev, GH_TOKEN env var

.PHONY: test test-unit test-integration test-lifecycle test-all \
        setup-fleet clean-fleet lint help

# Default target
test: test-unit

# Unit tests (fast, no external dependencies)
test-unit:
	@./tests/run_unit.sh

# Integration: messaging test only (requires existing fleet)
test-integration:
	@./tests/run_integration.sh

# Integration: full lifecycle test (creates and destroys its own fleet)
test-lifecycle:
	@./tests/run_integration.sh --lifecycle

# All tests: unit + all integration
test-all: test-unit
	@./tests/run_integration.sh --all

# Setup a test fleet (for manual testing or before test-integration)
setup-fleet:
	@./tests/run_integration.sh --setup
	@echo "Fleet ready. Run 'make test-integration' to test messaging."

# Clean up all VMs and local config
clean-fleet:
	@./ocaptain fleet sink --force --scuttle

# Lint shell scripts with shellcheck (matches .pre-commit-config.yaml)
lint:
	@echo "Running shellcheck..."
	@shellcheck -x -e SC2029 -e SC2088 -e SC1091 -e SC2016 \
		ocaptain tests/run_unit.sh tests/run_integration.sh \
		tests/unit/helpers/common.bash tests/lib/test_helpers.sh \
		tests/integration/*.sh cloudinit/init.sh
	@echo "All clear!"

# Help
help:
	@echo "ocaptain targets:"
	@echo ""
	@echo "  make test              Run unit tests (fast, default)"
	@echo "  make test-unit         Run unit tests"
	@echo "  make test-integration  Run messaging test (needs fleet)"
	@echo "  make test-lifecycle    Run lifecycle test (self-contained)"
	@echo "  make test-all          Run unit + all integration tests"
	@echo ""
	@echo "  make lint              Run shellcheck on all scripts"
	@echo "  make setup-fleet       Create a test fleet"
	@echo "  make clean-fleet       Destroy all VMs and config"
