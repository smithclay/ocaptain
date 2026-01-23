#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # BATS runs each test in a subshell; exports are intentionally local
# ==============================================================================
# Unit tests for ocaptain pure data functions
# ==============================================================================
#
# Tests pure data functions from the PURE DATA FUNCTIONS section (lines 145-206):
#   - _ocap_filter_ships_by_prefix: prefix matching on VM JSON
#   - _ocap_format_fleet_status_json: JSON formatting
#   - _ocap_format_fleet_status: text table formatting
#
# These functions have no side effects - they transform data, making them
# ideal candidates for unit testing.
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
# _ocap_filter_ships_by_prefix tests
# ==============================================================================

@test "_ocap_filter_ships_by_prefix matches exact prefix" {
  vms=$(sample_vms_json)
  result=$(_ocap_filter_ships_by_prefix "myrepo-def" "$vms")
  [ "$result" = "myrepo-def456" ]
}

@test "_ocap_filter_ships_by_prefix matches multiple ships" {
  vms=$(sample_vms_json)
  result=$(_ocap_filter_ships_by_prefix "myrepo" "$vms" | wc -l | tr -d ' ')
  [ "$result" -eq 2 ]
}

@test "_ocap_filter_ships_by_prefix returns empty for no match" {
  vms=$(sample_vms_json)
  result=$(_ocap_filter_ships_by_prefix "nonexistent" "$vms")
  [ -z "$result" ]
}

@test "_ocap_filter_ships_by_prefix filters out non-ship VMs" {
  vms=$(sample_vms_json)
  # The 'unrelated-vm' should not appear even if we try to match 'unrelated'
  result=$(_ocap_filter_ships_by_prefix "unrelated" "$vms")
  [ -z "$result" ]
}

@test "_ocap_filter_ships_by_prefix handles empty VM list" {
  result=$(_ocap_filter_ships_by_prefix "any" "[]")
  [ -z "$result" ]
}

@test "_ocap_filter_ships_by_prefix strips ship- prefix from results" {
  vms=$(sample_vms_json)
  result=$(_ocap_filter_ships_by_prefix "myrepo-def" "$vms")
  # Result should NOT contain 'ship-' prefix
  [[ "$result" != *"ship-"* ]]
}

# ==============================================================================
# _ocap_format_fleet_status_json tests
# ==============================================================================

@test "_ocap_format_fleet_status_json returns valid JSON" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship.example.com" "$vms" "$registry")
  # Verify it's valid JSON by parsing with jq
  echo "$result" | jq . >/dev/null 2>&1
}

@test "_ocap_format_fleet_status_json includes flagship hostname" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "my-flagship" "$vms" "$registry")
  flagship=$(echo "$result" | jq -r '.flagship')
  [ "$flagship" = "my-flagship" ]
}

@test "_ocap_format_fleet_status_json includes ships array" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  ship_count=$(echo "$result" | jq '.ships | length')
  [ "$ship_count" -eq 3 ]
}

@test "_ocap_format_fleet_status_json includes ship IDs without prefix" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  # First ship ID should not have 'ship-' prefix
  first_id=$(echo "$result" | jq -r '.ships[0].id')
  [[ "$first_id" != "ship-"* ]]
}

@test "_ocap_format_fleet_status_json includes repo from registry" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  # Check that myrepo-def456 has the correct repo
  repo=$(echo "$result" | jq -r '.ships[] | select(.id == "myrepo-def456") | .repo')
  [ "$repo" = "owner/myrepo" ]
}

@test "_ocap_format_fleet_status_json returns null for unregistered ship" {
  vms='[{"vm_name": "ship-unknown-xyz", "ssh_dest": "user@host", "status": "running"}]'
  registry='{}'
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  repo=$(echo "$result" | jq -r '.ships[0].repo')
  [ "$repo" = "null" ]
}

@test "_ocap_format_fleet_status_json includes ssh_dest" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  ssh_dest=$(echo "$result" | jq -r '.ships[] | select(.id == "myrepo-def456") | .ssh_dest')
  [ "$ssh_dest" = "user@ship1.example.com" ]
}

@test "_ocap_format_fleet_status_json includes status" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  status=$(echo "$result" | jq -r '.ships[] | select(.id == "other-jkl012") | .status')
  [ "$status" = "stopped" ]
}

@test "_ocap_format_fleet_status_json sorts ships by ID" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "$registry")
  # First should be alphabetically first (sorted by ID)
  first_id=$(echo "$result" | jq -r '.ships[0].id')
  [ "$first_id" = "myrepo-def456" ]
}

@test "_ocap_format_fleet_status_json handles empty registry" {
  vms=$(sample_vms_json)
  result=$(_ocap_format_fleet_status_json "flagship" "$vms" "{}")
  # Should still work, repos will be null
  ship_count=$(echo "$result" | jq '.ships | length')
  [ "$ship_count" -eq 3 ]
}

# ==============================================================================
# _ocap_format_fleet_status tests
# ==============================================================================

@test "_ocap_format_fleet_status shows flagship hostname" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status "my-flagship.example.com" "$vms" "$registry")
  [[ "$result" == *"FLAGSHIP: my-flagship.example.com"* ]]
}

@test "_ocap_format_fleet_status shows ship count" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  [[ "$result" == *"SHIPS (3)"* ]]
}

@test "_ocap_format_fleet_status shows no ships message when empty" {
  vms='[]'
  registry='{}'
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  [[ "$result" == *"SHIPS: (none)"* ]]
}

@test "_ocap_format_fleet_status includes column headers" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  [[ "$result" == *"SHIP"* ]]
  [[ "$result" == *"REPO"* ]]
  [[ "$result" == *"SSH_DEST"* ]]
  [[ "$result" == *"STATUS"* ]]
}

@test "_ocap_format_fleet_status shows ship IDs" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  [[ "$result" == *"myrepo-def456"* ]]
}

@test "_ocap_format_fleet_status shows repo names" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  [[ "$result" == *"owner/myrepo"* ]]
}

@test "_ocap_format_fleet_status shows dash for missing repo" {
  vms='[{"vm_name": "ship-noregistry-abc", "ssh_dest": "user@host", "status": "running"}]'
  registry='{}'
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  # Should show "-" for missing repo
  [[ "$result" == *"-"* ]]
}

@test "_ocap_format_fleet_status excludes non-ship VMs" {
  vms=$(sample_vms_json)
  registry=$(sample_registry_json)
  result=$(_ocap_format_fleet_status "flagship" "$vms" "$registry")
  # 'unrelated-vm' should not appear
  [[ "$result" != *"unrelated-vm"* ]]
  # Flagship VM should not appear in ships list (appears only in header)
  local count
  count=$(echo "$result" | grep -c "flagship-ocaptain" || true)
  [ "$count" -eq 0 ]
}
