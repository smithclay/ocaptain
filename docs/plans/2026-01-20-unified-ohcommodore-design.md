# Unified ohcommodore Design

## Summary

Consolidate all scripts (`ohcommodore`, `flagship/bin/*`) into a single bash script with identity awareness. One script runs everywhere - laptop, flagship, ships - with behavior determined by role.

## Identity Model

Three identities, one interface:

| Identity | Detection | Location |
|----------|-----------|----------|
| `local` | No `~/.ohcommodore/identity.json` | Your laptop |
| `commodore` | `{ "role": "commodore" }` | Flagship VM |
| `captain` | `{ "role": "captain" }` | Ship VMs |

```bash
get_role() {
  local id_file="$HOME/.ohcommodore/identity.json"
  if [[ -f "$id_file" ]]; then
    jq -r '.role' "$id_file"
  else
    echo "local"
  fi
}
```

## Command Routing

Same commands everywhere, smart routing based on role:

| Command | local | commodore | captain |
|---------|-------|-----------|---------|
| `ship create` | proxy to flagship | execute | error |
| `ship destroy` | proxy to flagship | execute | error |
| `fleet status` | proxy to flagship | execute | error |
| `inbox list` | error | execute | execute |
| `inbox send` | error | execute | execute |

**Routing pattern:**
```bash
cmd_ship_create() {
  case "$(get_role)" in
    local)
      flagship_ssh "ohcommodore ship create $(printf %q "$1")"
      ;;
    commodore)
      # actual implementation
      ;;
    captain)
      die "Cannot create ships from a ship"
      ;;
  esac
}
```

## Deployment Chain

```
Laptop (local)                  Flagship (commodore)              Ship (captain)
─────────────────────────────────────────────────────────────────────────────────
ohcommodore init
  ├─► ssh exe.dev new flagship-ohcommodore
  ├─► scp ohcommodore → flagship:~/.local/bin/ohcommodore
  ├─► ssh flagship "ohcommodore _init_commodore"
  │     └─► write identity.json { "role": "commodore" }
  │     └─► create DuckDB with fleet table
  │     └─► invoke init.sh for OS setup
  └─► save local config

ohcommodore ship create owner/repo
  │ (from laptop, proxies to flagship)
  └─► flagship executes:
        ├─► ssh exe.dev new ship-reponame
        ├─► scp ohcommodore → ship:~/.local/bin/ohcommodore
        ├─► ssh ship "ohcommodore _init_captain owner/repo"
        │     └─► write identity.json { "role": "captain" }
        │     └─► invoke init.sh for OS setup
        └─► INSERT into fleet table (name, repo, ssh_dest, pubkey)
```

## Data Architecture

**exe.dev** is source of truth for which VMs exist.

**DuckDB fleet table** (on flagship) augments exe.dev with metadata:
- `name` - ship name
- `repo` - GitHub repo association
- `ssh_dest` - SSH destination
- `pubkey` - ship's SSH public key
- `status` - running/stopped
- `created_at` - timestamp

**DuckDB inbox table** (on all VMs) for async messaging.

## File Structure

**Repository:**
```
ohcommodore                    # THE script - everywhere
cloudinit/init.sh              # OS-level setup (apt, tools, zsh, etc.)
```

**On each VM after init:**
```
~/.local/bin/ohcommodore       # the script
~/.ohcommodore/identity.json   # { "role": "commodore" } or { "role": "captain" }
~/.local/ship/data.duckdb      # inbox (+ fleet table on flagship)
```

## Command Reference

```bash
# Identity & init (internal, called during setup)
ohcommodore _init_commodore              # flagship setup
ohcommodore _init_captain <repo>         # ship setup
ohcommodore _scheduler                   # inbox daemon (systemd)

# Fleet management (local → flagship proxy)
ohcommodore init                         # bootstrap flagship
ohcommodore fleet status                 # show fleet
ohcommodore fleet sink [--force] [--scuttle]

# Ship management (local → flagship proxy)
ohcommodore ship create <owner/repo>
ohcommodore ship destroy <name>
ohcommodore ship ssh <name>

# Inbox (runs locally on VMs, errors on laptop)
ohcommodore inbox list [--status <status>]
ohcommodore inbox send <recipient> <command>
ohcommodore inbox read <id>
ohcommodore inbox done <id>
ohcommodore inbox error <id> <message>
ohcommodore inbox delete <id>
ohcommodore inbox identity
```

## Inbox Behavior by Role

| Role | Inbox commands |
|------|----------------|
| `local` | Error: "Inbox not available on local" |
| `commodore` | Execute locally |
| `captain` | Execute locally |

## Key Simplifications

1. **One script** instead of 4 (`ohcommodore` + 3 flagship scripts)
2. **scp deployment** - ohcommodore copies itself to VMs
3. **Role-based routing** - same interface everywhere
4. **init.sh stays separate** - OS provisioning invoked by ohcommodore
