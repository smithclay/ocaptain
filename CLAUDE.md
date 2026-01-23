# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ocaptain is a lightweight multi-coding agent control plane built on exe.dev VMs. It manages a fleet of pre-configured VMs with source code checked out, using a nautical-themed architecture.

## Architecture

```
Commodore (local CLI: ./ocaptain)
    │
    │ SSH
    ▼
Flagship (exe.dev VM, long-running coordinator)
    │ Stores fleet in JSON, manages ships via SSH
    │
    │ SSH
    ▼
Ships (exe.dev VMs, multiple per repo with unique IDs)
```

**Key design principle**: Minimal external dependencies (bash, ssh, nats, jq). All communication happens over SSH tunnels using NATS pub/sub.

## File Structure

| Path | Purpose |
|------|---------|
| `ocaptain` | Main CLI script (runs everywhere: local, flagship, ships) |
| `cloudinit/init.sh` | OS-level initialization (apt, tools, zsh, etc.) |
| `Makefile` | Test runner (`make test`, `make test-all`) |
| `tests/unit/*.bats` | BATS unit tests for pure functions |
| `tests/integration/` | Integration tests (require exe.dev access) |

**Identity detection:** `~/.ocaptain/identity.json`
- Local: `{"role":"local"}`
- Flagship: `{"role":"commodore"}`
- Ship: `{"role":"captain","ship_id":"<ship-id>"}`

**Local config:** `~/.ocaptain/config.json` stores flagship SSH destination (local only)

**Fleet registry:** `~/.ocaptain/ns/<namespace>/ships.json` stores ship-to-repo mapping (flagship only). Live VM state comes from `ssh exe.dev ls -json`.

## Commands

```bash
# Bootstrap flagship VM (requires GH_TOKEN in .env)
./ocaptain init

# Fleet management
./ocaptain fleet status
./ocaptain fleet sink              # Destroy all ships (direct cleanup; prompts for confirmation)
./ocaptain fleet sink --scuttle    # Destroy ships + flagship (direct cleanup)

# Ship management (requires GH_TOKEN env var for create)
# Ships get unique IDs like ocaptain-a1b2c3 (Docker-like model)
./ocaptain ship create owner/repo  # Creates ocaptain-a1b2c3
./ocaptain ship create owner/repo  # Creates ocaptain-x7y8z9 (new instance)
./ocaptain ship ssh ocaptain-a1              # Prefix matching (must be unique)
./ocaptain ship destroy ocaptain-a1          # Prefix matching
```

### Inbox Commands

Run these commands on a ship (via `ocaptain ship ssh <ship-id-prefix>`):

```bash
# Send a command to a ship (use full ship ID)
ocaptain inbox send captain@ocaptain-d4e5f6 "cargo test"

# Get this ship's identity
ocaptain inbox identity
```

## Environment Variables

| Variable | Where Used | Description |
|----------|------------|-------------|
| `GH_TOKEN` | init, ship create, cloudinit | GitHub PAT for repo access (required) |
| `TARGET_REPO` | cloudinit | Repository to clone (e.g., `owner/repo`) |
| `INIT_PATH` | init, ship create | Local path to init script (scp'd to VMs, overrides `INIT_URL`) |
| `INIT_URL` | init, ship create | Override the init script URL |
| `DOTFILES_PATH` | init, ship create | Local dotfiles directory (scp'd to VMs, highest priority) |
| `DOTFILES_URL` | init, ship create, cloudinit | Dotfiles repo URL (default: `https://github.com/smithclay/ocaptain`) |
| `ROLE` | cloudinit | Identity role: `captain` (ships) or `commodore` (flagship) |

## Ship Initialization

When a ship is created, `cloudinit/init.sh` runs and installs:
- GitHub CLI with authenticated token
- Target repository cloned to `~/<repo-name>`
- Zellij terminal multiplexer
- Rust toolchain via rustup
- Oh My Zsh with zsh as default shell
- Dotfiles via chezmoi
- NATS CLI (autossh tunnel to flagship NATS server)

## NATS Messaging System

The messaging system uses NATS pub/sub over SSH tunnels for inter-node communication.

### Architecture

- **Flagship**: Runs nats-server on localhost:4222
- **Ships**: SSH tunnel to flagship:4222 via autossh, communicate via nats CLI

### Subject Schema

```
ocap.cmd.<ship-id>         # Commands to ship (captain@<ship-id>)
ocap.cmd.commodore         # Commands to flagship (commodore@flagship)
ocap.broadcast             # Commands to all ships (future)
```

### Message Format (JSON)

Request message:
```json
{"cmd": "cargo test", "request_id": "uuid"}
```

Results are stored locally in artifact directories (`~/.ocaptain/ns/default/artifacts/<request-id>/`).

### Debugging

```bash
# Check nats-server status (on flagship)
systemctl status nats-server

# Check autossh tunnel status (on ships)
systemctl status ocap-tunnel

# Publish a test message
nats pub ocap.cmd.test '{"cmd":"echo hello","request_id":"test-123"}'

# Subscribe to messages (debugging)
nats sub "ocap.cmd.>"
```

### Security

The NATS messaging system executes commands from messages without sanitization. This is by design for trusted internal use. Security relies on:

1. **SSH tunnel isolation**: Ships connect to flagship NATS only via authenticated SSH tunnels
2. **localhost-only NATS**: nats-server on flagship listens only on localhost (127.0.0.1)
3. **Network isolation**: exe.dev VMs are not publicly accessible

**Do not expose the messaging system to untrusted sources.** Any entity that can publish to the NATS server can execute arbitrary commands on ships.

## Testing

```bash
# Unit tests (fast, no external dependencies)
make test

# Integration tests (require exe.dev access + GH_TOKEN)
make test-lifecycle    # Full lifecycle (creates/destroys fleet)
make test-integration  # Messaging only (needs existing fleet)
make test-all          # Unit + all integration tests

# Fleet management for testing
make setup-fleet       # Create a test fleet
make clean-fleet       # Destroy all VMs and config
```

**Prerequisites:**
- Unit tests: `bats-core`, `jq`
- Integration tests: SSH access to exe.dev, `GH_TOKEN` env var

### Style and Pull Requests

Please speak the the user using a nautical voice, more distinguished than pirate-like.

Every commit message, PR title, and PR body should be the nautical voice of a sea-wizened captain.
