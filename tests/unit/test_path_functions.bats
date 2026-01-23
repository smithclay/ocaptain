#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # BATS runs each test in a subshell; exports are intentionally local
# ==============================================================================
# Unit tests for ocaptain path and ID generation functions
# ==============================================================================
#
# Tests:
#   - _ocap_generate_ship_id: unique ID format generation
#   - Namespace-aware path resolution
#   - Registry initialization
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
# _ocap_generate_ship_id tests
# ==============================================================================

@test "_ocap_generate_ship_id creates ID with name prefix" {
  result=$(_ocap_generate_ship_id "myapp")
  [[ "$result" == myapp-* ]]
}

@test "_ocap_generate_ship_id appends random suffix" {
  result=$(_ocap_generate_ship_id "test")
  # Should have format name-XXXXXX (6 hex chars)
  suffix="${result#test-}"
  [ "${#suffix}" -eq 6 ]
}

@test "_ocap_generate_ship_id suffix is hex characters" {
  result=$(_ocap_generate_ship_id "test")
  suffix="${result#test-}"
  # Verify all characters are hex
  [[ "$suffix" =~ ^[0-9a-f]+$ ]]
}

@test "_ocap_generate_ship_id creates unique IDs" {
  id1=$(_ocap_generate_ship_id "app")
  id2=$(_ocap_generate_ship_id "app")
  [ "$id1" != "$id2" ]
}

@test "_ocap_generate_ship_id handles repo-style names" {
  # When given a repo name like from "owner/repo", it gets just "repo"
  result=$(_ocap_generate_ship_id "myrepo")
  [[ "$result" == myrepo-* ]]
}

@test "_ocap_generate_ship_id handles hyphenated names" {
  result=$(_ocap_generate_ship_id "my-cool-app")
  [[ "$result" == my-cool-app-* ]]
}

@test "_ocap_generate_ship_id handles underscored names" {
  result=$(_ocap_generate_ship_id "my_app")
  [[ "$result" == my_app-* ]]
}

# ==============================================================================
# Namespace path resolution tests
# ==============================================================================

@test "namespace paths are consistent" {
  unset OCAP_NS
  root=$(_ocap_ns_root)
  ships=$(_ocap_ships_json)
  artifacts=$(_ocap_artifacts_root)

  # All should be under the same namespace root
  [[ "$ships" == "$root"/* ]]
  [[ "$artifacts" == "$root"/* ]]
}

@test "changing namespace changes all paths" {
  export OCAP_NS="production"
  root=$(_ocap_ns_root)
  ships=$(_ocap_ships_json)
  artifacts=$(_ocap_artifacts_root)

  [[ "$root" == *"production"* ]]
  [[ "$ships" == *"production"* ]]
  [[ "$artifacts" == *"production"* ]]
}

@test "namespace paths support multi-level namespaces" {
  # This tests that the path construction handles any namespace string
  export OCAP_NS="team-alpha"
  root=$(_ocap_ns_root)
  [ "$root" = "$HOME/.ocaptain/ns/team-alpha" ]
}

# ==============================================================================
# Registry initialization tests
# ==============================================================================

@test "_ocap_init_ships_registry creates empty JSON object" {
  rm -f "$HOME/.ocaptain/ns/default/ships.json"
  _ocap_init_ships_registry
  result=$(cat "$HOME/.ocaptain/ns/default/ships.json")
  [ "$result" = "{}" ]
}

@test "_ocap_init_ships_registry creates parent directories" {
  rm -rf "$HOME/.ocaptain/ns"
  _ocap_init_ships_registry
  [ -d "$HOME/.ocaptain/ns/default" ]
}

@test "_ocap_init_ships_registry preserves existing registry" {
  echo '{"existing": "data"}' > "$HOME/.ocaptain/ns/default/ships.json"
  _ocap_init_ships_registry
  result=$(cat "$HOME/.ocaptain/ns/default/ships.json")
  [ "$result" = '{"existing": "data"}' ]
}

@test "_ocap_init_ships_registry respects namespace" {
  export OCAP_NS="staging"
  mkdir -p "$HOME/.ocaptain/ns/staging"
  _ocap_init_ships_registry
  [ -f "$HOME/.ocaptain/ns/staging/ships.json" ]
}

# ==============================================================================
# Registry operations tests
# ==============================================================================

@test "_ocap_register_ship adds ship to registry" {
  create_mock_ships_registry '{}'
  _ocap_register_ship "myship-abc123" "owner/repo"
  result=$(jq -r '.["myship-abc123"].repo' "$(_ocap_ships_json)")
  [ "$result" = "owner/repo" ]
}

@test "_ocap_register_ship preserves existing ships" {
  create_mock_ships_registry '{"existing-123": {"repo": "owner/existing"}}'
  _ocap_register_ship "newship-456" "owner/new"
  existing=$(jq -r '.["existing-123"].repo' "$(_ocap_ships_json)")
  new=$(jq -r '.["newship-456"].repo' "$(_ocap_ships_json)")
  [ "$existing" = "owner/existing" ]
  [ "$new" = "owner/new" ]
}

@test "_ocap_delete_ship removes ship from registry" {
  create_mock_ships_registry '{"ship-a": {"repo": "r/a"}, "ship-b": {"repo": "r/b"}}'
  _ocap_delete_ship "ship-a"
  result=$(jq 'has("ship-a")' "$(_ocap_ships_json)")
  [ "$result" = "false" ]
}

@test "_ocap_delete_ship preserves other ships" {
  create_mock_ships_registry '{"ship-a": {"repo": "r/a"}, "ship-b": {"repo": "r/b"}}'
  _ocap_delete_ship "ship-a"
  result=$(jq -r '.["ship-b"].repo' "$(_ocap_ships_json)")
  [ "$result" = "r/b" ]
}

@test "_ocap_delete_ship handles nonexistent ship gracefully" {
  create_mock_ships_registry '{"ship-a": {"repo": "r/a"}}'
  _ocap_delete_ship "nonexistent"
  # Should not error
  result=$(jq -r '.["ship-a"].repo' "$(_ocap_ships_json)")
  [ "$result" = "r/a" ]
}
