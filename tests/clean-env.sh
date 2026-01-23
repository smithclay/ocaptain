#!/usr/bin/env bash
# Clean up orphaned test VMs and local state
#
# Usage:
#   ./tests/clean-env.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Cleaning up test environment..."

# Remove all VMs on exe.dev
echo -e "${YELLOW}Checking for VMs on exe.dev...${NC}"
# Parse VM names from JSON output
all_vms=$(ssh exe.dev ls --json 2>/dev/null | jq -r '.vms[]?.vm_name // empty' || true)
if [[ -n "$all_vms" ]]; then
  vm_count=$(echo "$all_vms" | wc -l | tr -d ' ')
  echo "Found $vm_count VMs to delete"
  for vm in $all_vms; do
    [[ -n "$vm" ]] || continue
    echo "Deleting $vm..."
    ssh exe.dev rm "$vm" 2>/dev/null || true
  done
  echo -e "${GREEN}Deleted all VMs${NC}"
else
  echo "No VMs found"
fi

# Remove local state
echo -e "${YELLOW}Removing local ocaptain state...${NC}"
if [[ -d "$HOME/.ocaptain" ]]; then
  rm -rf "$HOME/.ocaptain"
  echo -e "${GREEN}Removed ~/.ocaptain${NC}"
else
  echo "No local state found"
fi

echo ""
# Remove SSH keys created by ocaptain (comment contains "ocaptain")
echo -e "${YELLOW}Checking for ocaptain SSH keys on exe.dev...${NC}"
ocap_keys=$(ssh exe.dev ssh-key list --json 2>/dev/null | jq -r '.ssh_keys[] | select(.comment != null and (.comment | contains("ocaptain")) and .current == false) | .public_key' || true)
if [[ -n "$ocap_keys" ]]; then
  key_count=$(echo "$ocap_keys" | wc -l | tr -d ' ')
  echo "Found $key_count ocaptain SSH keys to remove"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    echo "Removing key: ${key:0:50}..."
    ssh -n exe.dev ssh-key remove "$key" 2>/dev/null || true
  done <<< "$ocap_keys"
  echo -e "${GREEN}Removed ocaptain SSH keys${NC}"
else
  echo "No ocaptain SSH keys found"
fi

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
