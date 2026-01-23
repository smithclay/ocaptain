# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ohcommodore is a lightweight multi-coding agent control plane built on exe.dev VMs. It manages a fleet of pre-configured VMs with source code checked out, using a nautical-themed architecture.

## Architecture

```
Commodore (local CLI: ./ohcommodore)
    │
    │ SSH
    ▼
Flagship (exe.dev VM, long-running coordinator)
    │ Stores fleet in DuckDB, manages ships via SSH
    │
    │ SSH
    ▼
Ships (exe.dev VMs, multiple per repo with unique IDs)
```

**Key design principle**: Minimal external dependencies (bash, ssh, opensmtpd, duckdb). All communication happens over SSH tunnels using email.

## File Structure

| Path | Purpose |
|------|---------|
| `ohcommodore` | Main CLI script (runs everywhere: local, flagship, ships) |
| `cloudinit/init.sh` | OS-level initialization (apt, tools, zsh, etc.) |

**Identity detection:** `~/.ohcommodore/identity.json` with `{"role":"local|commodore|captain"}`

**Local config:** `~/.ohcommodore/config.json` stores flagship SSH destination (local only)

**VM state:** `~/.ohcommodore/ns/<namespace>/data.duckdb` stores fleet registry (flagship), local config, and messages.

## Commands

```bash
# Bootstrap flagship VM (requires GH_TOKEN)
GH_TOKEN=... ./ohcommodore init

# Fleet management
./ohcommodore fleet status
./ohcommodore fleet sink              # Destroy all ships (direct cleanup; prompts for confirmation)
./ohcommodore fleet sink --scuttle    # Destroy ships + flagship (direct cleanup)

# Ship management (requires GH_TOKEN env var for create)
# Ships get unique IDs like ohcommodore-a1b2c3 (Docker-like model)
GH_TOKEN=... ./ohcommodore ship create owner/repo  # Creates ohcommodore-a1b2c3
GH_TOKEN=... ./ohcommodore ship create owner/repo  # Creates ohcommodore-x7y8z9 (new instance)
./ohcommodore ship ssh ohcommodore-a1              # Prefix matching (must be unique)
./ohcommodore ship destroy ohcommodore-a1          # Prefix matching
```

### Inbox Commands

Run these commands on a ship (via `ohcommodore ship ssh <ship-id-prefix>`):

```bash
# List inbox messages
ohcommodore inbox list
ohcommodore inbox list --status done

# Send a command to another ship (use full ship ID)
ohcommodore inbox send captain@ohcommodore-d4e5f6 "cargo test"

# Send a command to commodore
ohcommodore inbox send commodore@flagship-host "echo 'Report from ship'"

# Get this ship's identity
ohcommodore inbox identity

# Manual message management
ohcommodore inbox read <id>        # Mark as read and return raw message content
```

## Environment Variables

| Variable | Where Used | Description |
|----------|------------|-------------|
| `GH_TOKEN` | init, ship create, cloudinit | GitHub PAT for repo access (required) |
| `TARGET_REPO` | cloudinit | Repository to clone (e.g., `owner/repo`) |
| `INIT_PATH` | init, ship create | Local path to init script (scp'd to VMs, overrides `INIT_URL`) |
| `INIT_URL` | init, ship create | Override the init script URL |
| `DOTFILES_PATH` | init, ship create | Local dotfiles directory (scp'd to VMs, highest priority) |
| `DOTFILES_URL` | init, ship create, cloudinit | Dotfiles repo URL (default: `https://github.com/smithclay/ohcommodore`) |
| `ROLE` | cloudinit | Identity role: `captain` (ships) or `commodore` (flagship) |

## Ship Initialization

When a ship is created, `cloudinit/init.sh` runs and installs:
- GitHub CLI with authenticated token
- Target repository cloned to `~/<repo-name>`
- Zellij terminal multiplexer
- Rust toolchain via rustup
- Oh My Zsh with zsh as default shell
- Dotfiles via chezmoi
- DuckDB CLI and email messaging (autossh tunnel to flagship SMTP)

## Email Messaging System

The messaging system uses email over SSH tunnels for inter-node communication.

### Architecture

- **Flagship**: Runs OpenSMTPD on localhost:25, delivers to per-identity Maildirs
- **Ships**: SSH tunnel to flagship:25 via autossh, send mail via msmtp (sendmail-compatible)
- **Storage**: Standard Maildir format (`~/Maildir/<domain>/{new,cur,tmp}`) where `<domain>` is extracted from the identity (e.g., `captain@ohcommodore-abc123` → `~/Maildir/ohcommodore-abc123/`)

### Message Format

Messages are standard RFC 5322 emails with custom `X-Ohcom-*` headers:

```
From: commodore@flagship
To: captain@ohcommodore-abc123
Subject: cmd.exec
Message-ID: <uuid@flagship>
Date: Mon, 20 Jan 2026 19:12:03 +0000
X-Ohcom-Topic: cmd.exec
X-Ohcom-Request-ID: req-123

cd ~/myrepo && cargo test
```

Result messages include an exit code header:

```
X-Ohcom-Topic: cmd.result
X-Ohcom-Request-ID: req-123
X-Ohcom-Exit-Code: 0
```

### Protocol Topics

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `cmd.exec` | → ship | Execute a command |
| `cmd.result` | ← ship | Return execution result |

### Debugging

```bash
# See pending messages (on flagship)
ls ~/Maildir/*/new/

# Check OpenSMTPD status (on flagship)
systemctl status opensmtpd
smtpctl show queue

# Check autossh tunnel status (on ships)
systemctl status ohcom-tunnel

# Read message history with mutt
mutt -f ~/Maildir/commodore/

# Watch for new mail
watch -n1 'ls ~/Maildir/*/new/'
```

### Security

The email messaging system executes commands from `cmd.exec` messages without sanitization. This is by design for trusted internal use. Security relies on:

1. **SSH tunnel isolation**: Ships connect to flagship SMTP only via authenticated SSH tunnels
2. **localhost-only SMTP**: OpenSMTPD on flagship listens only on localhost (127.0.0.1)
3. **Network isolation**: exe.dev VMs are not publicly accessible

**Do not expose the messaging system to untrusted sources.** Any entity that can send mail to the flagship can execute arbitrary commands on ships.
