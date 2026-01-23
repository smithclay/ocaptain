#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # BATS runs each test in a subshell; exports are intentionally local
# ==============================================================================
# Unit tests for ocaptain core utility functions
# ==============================================================================
#
# Tests pure functions from the CORE UTILITIES section (lines 62-135):
#   - _ocap_log: stderr output
#   - _ocap_shell_quote: special character escaping
#   - _ocap_ns: namespace resolution
#   - _ocap_ns_root, _ocap_ships_json, _ocap_artifacts_root: path generation
#   - _ocap_get_role: identity file parsing
#   - _ocap_need_cmd: command existence check
#
# ==============================================================================

load 'helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ==============================================================================
# _ocap_log tests
# ==============================================================================

@test "_ocap_log writes to stderr with prefix" {
  run bash -c 'source '"$PROJECT_ROOT"'/ocaptain && _ocap_log "test message" 2>&1'
  [ "$status" -eq 0 ]
  [ "$output" = "==> test message" ]
}

@test "_ocap_log handles multiple arguments" {
  run bash -c 'source '"$PROJECT_ROOT"'/ocaptain && _ocap_log "hello" "world" 2>&1'
  [ "$status" -eq 0 ]
  [ "$output" = "==> hello world" ]
}

# ==============================================================================
# _ocap_shell_quote tests
# ==============================================================================

@test "_ocap_shell_quote escapes single quotes" {
  result=$(_ocap_shell_quote "it's")
  # Should contain an escape mechanism for the quote
  [[ "$result" != "it's" ]]
  # Eval should give back original
  local restored
  eval "restored=$result"
  [ "$restored" = "it's" ]
}

@test "_ocap_shell_quote escapes spaces" {
  result=$(_ocap_shell_quote "hello world")
  local restored
  eval "restored=$result"
  [ "$restored" = "hello world" ]
}

@test "_ocap_shell_quote escapes special chars" {
  result=$(_ocap_shell_quote 'foo$bar`baz')
  local restored
  eval "restored=$result"
  [ "$restored" = 'foo$bar`baz' ]
}

@test "_ocap_shell_quote handles empty string" {
  result=$(_ocap_shell_quote "")
  [ -n "$result" ]  # Should output something (quotes)
}

# ==============================================================================
# _ocap_ns tests
# ==============================================================================

@test "_ocap_ns returns default namespace when OCAP_NS unset" {
  unset OCAP_NS
  result=$(_ocap_ns)
  [ "$result" = "default" ]
}

@test "_ocap_ns returns OCAP_NS when set" {
  export OCAP_NS="production"
  result=$(_ocap_ns)
  [ "$result" = "production" ]
}

@test "_ocap_ns returns custom namespace" {
  export OCAP_NS="staging"
  result=$(_ocap_ns)
  [ "$result" = "staging" ]
}

# ==============================================================================
# Path generation tests
# ==============================================================================

@test "_ocap_ns_root returns correct path for default namespace" {
  unset OCAP_NS
  result=$(_ocap_ns_root)
  [ "$result" = "$HOME/.ocaptain/ns/default" ]
}

@test "_ocap_ns_root returns correct path for custom namespace" {
  export OCAP_NS="production"
  result=$(_ocap_ns_root)
  [ "$result" = "$HOME/.ocaptain/ns/production" ]
}

@test "_ocap_ships_json returns correct path" {
  unset OCAP_NS
  result=$(_ocap_ships_json)
  [ "$result" = "$HOME/.ocaptain/ns/default/ships.json" ]
}

@test "_ocap_artifacts_root returns correct path" {
  unset OCAP_NS
  result=$(_ocap_artifacts_root)
  [ "$result" = "$HOME/.ocaptain/ns/default/artifacts" ]
}

# ==============================================================================
# _ocap_get_role tests
# ==============================================================================

@test "_ocap_get_role returns local when no identity file" {
  rm -f "$HOME/.ocaptain/identity.json"
  result=$(_ocap_get_role)
  [ "$result" = "local" ]
}

@test "_ocap_get_role returns commodore from identity file" {
  create_mock_identity "commodore"
  result=$(_ocap_get_role)
  [ "$result" = "commodore" ]
}

@test "_ocap_get_role returns captain from identity file" {
  create_mock_identity "captain"
  result=$(_ocap_get_role)
  [ "$result" = "captain" ]
}

@test "_ocap_get_role returns local for invalid JSON" {
  echo "not valid json" > "$HOME/.ocaptain/identity.json"
  result=$(_ocap_get_role)
  [ "$result" = "local" ]
}

@test "_ocap_get_role returns local when role missing" {
  echo '{"other": "field"}' > "$HOME/.ocaptain/identity.json"
  result=$(_ocap_get_role)
  [ "$result" = "local" ]
}

# ==============================================================================
# _ocap_need_cmd tests
# ==============================================================================

@test "_ocap_need_cmd succeeds for existing command" {
  run _ocap_need_cmd "bash"
  [ "$status" -eq 0 ]
}

@test "_ocap_need_cmd succeeds for common utilities" {
  run _ocap_need_cmd "cat"
  [ "$status" -eq 0 ]
}

@test "_ocap_need_cmd fails for nonexistent command" {
  run _ocap_need_cmd "definitely_not_a_real_command_12345"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required command"* ]]
}

# ==============================================================================
# _ocap_uuid_gen tests
# ==============================================================================

@test "_ocap_uuid_gen returns a value" {
  result=$(_ocap_uuid_gen)
  [ -n "$result" ]
}

@test "_ocap_uuid_gen returns different values" {
  uuid1=$(_ocap_uuid_gen)
  uuid2=$(_ocap_uuid_gen)
  [ "$uuid1" != "$uuid2" ]
}

@test "_ocap_uuid_gen returns valid-looking UUID" {
  result=$(_ocap_uuid_gen)
  # UUIDs typically have 32 hex chars with optional dashes
  # Check for reasonable length
  [ "${#result}" -ge 32 ]
}
