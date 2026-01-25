# CLAUDE.md

## Project Overview

ocaptain is a lightweight multi-coding agent control plane.

## CLI Commands

- `ocaptain sail -r <repo> "<prompt>"` - Launch a new voyage
- `ocaptain status [voyage_id]` - Show voyage status
- `ocaptain logs <voyage_id>` - View aggregated logs
- `ocaptain tasks <voyage_id>` - Show task list
- `ocaptain resume <voyage_id>` - Add ships to an incomplete voyage
- `ocaptain shell <voyage_id> <ship_id>` - SSH into a ship
- `ocaptain sink <voyage_id>` - Destroy ships (keeps storage by default)
  - `--include-storage, -s` - Also destroy storage VM
  - `--all` - Destroy ALL ocaptain VMs
  - `--force, -f` - Skip confirmation
- `ocaptain reset-task <voyage_id> <task_id>` - Reset stale task to pending
