# Unified ohcommodore Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate all scripts into a single identity-aware `ohcommodore` bash script.

**Architecture:** Add role detection via `~/.ohcommodore/identity.json`. Commands check role and either execute directly or proxy via SSH. The script copies itself to VMs during init.

**Tech Stack:** Bash, jq, DuckDB, SSH

---

## Task 1: Add Identity Detection

**Files:**
- Modify: `ohcommodore:1-30` (add after existing helpers)

**Step 1: Add get_role function**

Add after line 28 (after `flagship_ssh`):

```bash
get_role() {
  local id_file="$HOME/.ohcommodore/identity.json"
  if [[ -f "$id_file" ]]; then
    jq -r '.role' "$id_file"
  else
    echo "local"
  fi
}

require_role() {
  local allowed=("$@")
  local current
  current=$(get_role)
  for role in "${allowed[@]}"; do
    [[ "$current" == "$role" ]] && return 0
  done
  die "Command not available for role '$current'. Allowed: ${allowed[*]}"
}
```

**Step 2: Verify manually**

```bash
# Test local (no identity file)
source ohcommodore; get_role
# Expected: local

# Test with identity file
mkdir -p ~/.ohcommodore
echo '{"role":"test"}' > ~/.ohcommodore/identity.json
source ohcommodore; get_role
# Expected: test

# Cleanup
rm ~/.ohcommodore/identity.json
```

**Step 3: Commit**

```bash
git add ohcommodore
git commit -m "feat: add identity detection (get_role, require_role)"
```

---

## Task 2: Add Internal Init Commands

**Files:**
- Modify: `ohcommodore` (add new command functions and case branches)

**Step 1: Add _init_commodore command**

Add before `show_help()`:

```bash
cmd__init_commodore() {
  require_role commodore local  # can be run during setup

  log "Initializing commodore identity..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/identity.json" <<'EOF'
{"role":"commodore"}
EOF

  log "Initializing fleet database..."
  mkdir -p ~/.local/ship
  duckdb ~/.local/ship/data.duckdb "
    CREATE TABLE IF NOT EXISTS fleet (
      name TEXT PRIMARY KEY,
      repo TEXT NOT NULL,
      ssh_dest TEXT NOT NULL,
      pubkey TEXT,
      status TEXT DEFAULT 'running',
      created_at TIMESTAMP DEFAULT current_timestamp
    );
  "

  # Run OS-level init if init.sh URL provided
  if [[ -n "${INIT_URL:-}" ]]; then
    log "Running OS init script..."
    curl -fsSL "$INIT_URL" | GH_TOKEN="${GH_TOKEN:-}" ROLE=commodore bash
  fi

  log "Commodore initialized."
}
```

**Step 2: Add _init_captain command**

Add after `cmd__init_commodore`:

```bash
cmd__init_captain() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || die "Usage: ohcommodore _init_captain <owner/repo>"

  log "Initializing captain identity..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/identity.json" <<EOF
{"role":"captain"}
EOF

  # Run OS-level init
  if [[ -n "${INIT_URL:-}" ]]; then
    log "Running OS init script..."
    curl -fsSL "$INIT_URL" | GH_TOKEN="${GH_TOKEN:-}" TARGET_REPO="$repo" ROLE=captain bash
  fi

  log "Captain initialized for $repo."
}
```

**Step 3: Add case branches**

Add to the main case statement before the `*` catch-all:

```bash
  _init_commodore) cmd__init_commodore ;;
  _init_captain) cmd__init_captain "${2:-}" ;;
```

**Step 4: Commit**

```bash
git add ohcommodore
git commit -m "feat: add _init_commodore and _init_captain commands"
```

---

## Task 3: Refactor cmd_init to Use Self-Copy

**Files:**
- Modify: `ohcommodore` (rewrite cmd_init)

**Step 1: Replace cmd_init function**

Replace the entire `cmd_init` function with:

```bash
cmd_init() {
  require_role local
  need_cmd ssh
  need_cmd jq
  need_cmd scp

  [[ -n "${GH_TOKEN:-}" ]] || die "GH_TOKEN env var required for flagship init"
  [[ -f "$CONFIG_FILE" ]] && die "Already initialized. Config: $CONFIG_FILE"

  log "Creating flagship VM..."
  create_json=$(ssh exe.dev new --json --name="flagship-ohcommodore" --no-email) \
    || die "Failed to create flagship VM"

  ssh_dest=$(echo "$create_json" | jq -r '.ssh_dest // empty')
  [[ -n "$ssh_dest" ]] || die "Failed to get ssh_dest from: $create_json"

  log "Flagship created: $ssh_dest"
  log "Waiting for SSH..."
  sleep 5

  wait_for_ssh "$ssh_dest" || die "SSH never became ready for $ssh_dest"

  log "Deploying ohcommodore to flagship..."
  ssh "$ssh_dest" 'mkdir -p ~/.local/bin'
  scp -q "$SCRIPT_DIR/ohcommodore" "${ssh_dest}:~/.local/bin/ohcommodore"
  ssh "$ssh_dest" 'chmod +x ~/.local/bin/ohcommodore'

  # Generate SSH key on flagship and register with exe.dev
  log "Setting up flagship SSH key..."
  flagship_pubkey=$(ssh "$ssh_dest" 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q 2>/dev/null || true; cat ~/.ssh/id_ed25519.pub')
  ssh exe.dev ssh-key add "$flagship_pubkey" || log "Warning: Could not add flagship SSH key (may already exist)"
  ssh "$ssh_dest" 'ssh -o StrictHostKeyChecking=accept-new exe.dev whoami >/dev/null 2>&1' || true

  # Run internal init command on flagship
  local init_url="${INIT_URL:-https://raw.githubusercontent.com/smithclay/ohcommodore/main/cloudinit/init.sh}"
  log "Running commodore init on flagship..."
  ssh "$ssh_dest" \
    "GH_TOKEN=$(printf %q "$GH_TOKEN") INIT_URL=$(printf %q "$init_url") ~/.local/bin/ohcommodore _init_commodore"

  log "Saving local config..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
{
  "flagship": "$ssh_dest",
  "flagship_vm": "flagship-ohcommodore",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  log "Done! Flagship ready at: $ssh_dest"
  log "Run 'ohcommodore fleet status' to verify."
}
```

**Step 2: Commit**

```bash
git add ohcommodore
git commit -m "refactor: cmd_init uses self-copy instead of flagship/bin scripts"
```

---

## Task 4: Inline Ship Create Logic

**Files:**
- Modify: `ohcommodore` (expand cmd_ship_create with role routing)

**Step 1: Replace cmd_ship_create with role-aware version**

Replace the entire `cmd_ship_create` function:

```bash
cmd_ship_create() {
  local repo="$1"
  [[ -n "$repo" ]] || die "Usage: ohcommodore ship create <owner/repo>"
  [[ -n "${GH_TOKEN:-}" ]] || die "GH_TOKEN env var required"

  case "$(get_role)" in
    local)
      need_flagship
      log "Creating ship '$repo' (via flagship)..."
      local init_url_env=""
      [[ -n "${INIT_URL:-}" ]] && init_url_env="INIT_URL=$(printf %q "$INIT_URL")"
      flagship_ssh "GH_TOKEN=$(printf %q "$GH_TOKEN") $init_url_env ~/.local/bin/ohcommodore ship create $(printf %q "$repo")"
      ;;
    commodore)
      _ship_create_impl "$repo"
      ;;
    captain)
      die "Cannot create ships from a ship"
      ;;
  esac
}

_ship_create_impl() {
  local repo="$1"
  local name="${repo##*/}"

  local init_url="${INIT_URL:-https://raw.githubusercontent.com/smithclay/ohcommodore/main/cloudinit/init.sh}"

  log "Generating SSH key for ship..."
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  ssh-keygen -t ed25519 -N "" -f "$tmpdir/ship_key" -q
  local ship_privkey ship_pubkey
  ship_privkey=$(cat "$tmpdir/ship_key")
  ship_pubkey=$(cat "$tmpdir/ship_key.pub")

  log "Registering ship SSH key with exe.dev..."
  ssh exe.dev ssh-key add "$ship_pubkey" || log "Warning: Could not add ship SSH key (may already exist)"

  local ship_privkey_b64 ship_pubkey_b64
  ship_privkey_b64=$(echo "$ship_privkey" | base64 -w0)
  ship_pubkey_b64=$(echo "$ship_pubkey" | base64 -w0)

  log "Creating ship VM..."
  local create_json
  create_json=$(ssh exe.dev new --json \
    --name="ship-${name}" \
    --no-email \
    --env GH_TOKEN="$GH_TOKEN" \
    --env TARGET_REPO="$repo" \
    --env SHIP_SSH_PRIVKEY_B64="$ship_privkey_b64" \
    --env SHIP_SSH_PUBKEY_B64="$ship_pubkey_b64") || true

  local error_msg
  error_msg=$(echo "$create_json" | jq -r '.error // empty')
  [[ -z "$error_msg" ]] || die "VM creation failed: $error_msg"

  local ssh_dest
  ssh_dest=$(echo "$create_json" | jq -r '.ssh_dest')
  [[ -n "$ssh_dest" && "$ssh_dest" != "null" ]] || die "Failed to get ssh_dest from: $create_json"

  log "Ship VM created: $ssh_dest"

  log "Waiting for DNS..."
  local hostname="${ssh_dest%%:*}"
  for ((i=1; i<=10; i++)); do
    if host "$hostname" >/dev/null 2>&1; then
      log "DNS resolved: $hostname"
      sleep 5
      break
    fi
    log "DNS not ready ($i/10)..."
    sleep 3
  done

  log "Waiting for SSH..."
  wait_for_ssh "$ssh_dest" || die "SSH never became ready for $ssh_dest"

  log "Deploying ohcommodore to ship..."
  ssh -o StrictHostKeyChecking=accept-new "$ssh_dest" 'mkdir -p ~/.local/bin'
  scp -q ~/.local/bin/ohcommodore "${ssh_dest}:~/.local/bin/ohcommodore"
  ssh "$ssh_dest" 'chmod +x ~/.local/bin/ohcommodore'

  log "Running captain init on ship..."
  ssh "$ssh_dest" \
    "GH_TOKEN=$(printf %q "$GH_TOKEN") INIT_URL=$(printf %q "$init_url") SHIP_SSH_PRIVKEY_B64=$(printf %q "$ship_privkey_b64") SHIP_SSH_PUBKEY_B64=$(printf %q "$ship_pubkey_b64") ~/.local/bin/ohcommodore _init_captain $(printf %q "$repo")"

  log "Registering ship in fleet..."
  local escaped_name escaped_repo escaped_dest escaped_pubkey
  escaped_name=$(printf '%s' "$name" | sed "s/'/''/g")
  escaped_repo=$(printf '%s' "$repo" | sed "s/'/''/g")
  escaped_dest=$(printf '%s' "$ssh_dest" | sed "s/'/''/g")
  escaped_pubkey=$(printf '%s' "$ship_pubkey" | sed "s/'/''/g")

  duckdb ~/.local/ship/data.duckdb "
    INSERT OR REPLACE INTO fleet (name, repo, ssh_dest, pubkey, status, created_at)
    VALUES ('$escaped_name', '$escaped_repo', '$escaped_dest', '$escaped_pubkey', 'running', current_timestamp);
  "

  log "Ship ready: $ssh_dest"
}
```

**Step 2: Commit**

```bash
git add ohcommodore
git commit -m "feat: inline ship create logic with role-based routing"
```

---

## Task 5: Inline Ship Destroy Logic

**Files:**
- Modify: `ohcommodore` (expand cmd_ship_destroy with role routing)

**Step 1: Replace cmd_ship_destroy with role-aware version**

Replace the entire `cmd_ship_destroy` function:

```bash
cmd_ship_destroy() {
  local name="$1"
  [[ -n "$name" ]] || die "Usage: ohcommodore ship destroy <name>"

  case "$(get_role)" in
    local)
      need_flagship
      log "Destroying ship '$name' (via flagship)..."
      flagship_ssh "~/.local/bin/ohcommodore ship destroy $(printf %q "$name")"
      ;;
    commodore)
      _ship_destroy_impl "$name"
      ;;
    captain)
      die "Cannot destroy ships from a ship"
      ;;
  esac
}

_ship_destroy_impl() {
  local name="$1"
  local escaped_name
  escaped_name=$(printf '%s' "$name" | sed "s/'/''/g")

  local ship_pubkey
  ship_pubkey=$(duckdb ~/.local/ship/data.duckdb -noheader -csv "SELECT pubkey FROM fleet WHERE name = '$escaped_name'" 2>/dev/null || echo "")

  log "Removing VM ship-${name}..."
  ssh exe.dev rm "ship-${name}" || true

  if [[ -n "$ship_pubkey" ]]; then
    log "Removing ship SSH key from exe.dev..."
    ssh exe.dev ssh-key remove "$ship_pubkey" 2>/dev/null || true
  fi

  log "Removing from fleet registry..."
  duckdb ~/.local/ship/data.duckdb "DELETE FROM fleet WHERE name = '$escaped_name'"

  log "Ship '$name' destroyed."
}
```

**Step 2: Commit**

```bash
git add ohcommodore
git commit -m "feat: inline ship destroy logic with role-based routing"
```

---

## Task 6: Add Role Routing to Fleet Commands

**Files:**
- Modify: `ohcommodore` (update cmd_fleet_status, cmd_fleet_sink)

**Step 1: Update cmd_fleet_status**

Replace the function:

```bash
cmd_fleet_status() {
  case "$(get_role)" in
    local)
      need_flagship
      flagship_ssh "~/.local/bin/ohcommodore fleet status"
      ;;
    commodore)
      _fleet_status_impl
      ;;
    captain)
      die "Fleet status not available from ships"
      ;;
  esac
}

_fleet_status_impl() {
  echo "FLAGSHIP: $(hostname -f 2>/dev/null || hostname)"
  echo ""

  local fleet_data
  fleet_data=$(duckdb ~/.local/ship/data.duckdb -noheader -csv "SELECT name, repo, status, pubkey FROM fleet ORDER BY created_at" 2>/dev/null || echo "")

  if [[ -z "$fleet_data" ]]; then
    echo "SHIPS: (none)"
  else
    local ship_count
    ship_count=$(echo "$fleet_data" | wc -l | tr -d ' ')
    local registered_keys
    registered_keys=$(ssh exe.dev ssh-key list 2>/dev/null || echo "")

    echo "SHIPS ($ship_count):"
    printf "  %-15s %-30s %-10s %s\n" "NAME" "REPO" "STATUS" "KEY"
    echo "$fleet_data" | while IFS=',' read -r name repo status pubkey; do
      local key_status="none"
      if [[ -n "$pubkey" ]]; then
        local key_part
        key_part=$(echo "$pubkey" | awk '{print $1" "$2}')
        if echo "$registered_keys" | grep -qF "$key_part"; then
          key_status="registered"
        else
          key_status="unregistered"
        fi
      fi
      printf "  %-15s %-30s %-10s %s\n" "$name" "$repo" "$status" "$key_status"
    done
  fi
}
```

**Step 2: Update cmd_fleet_sink**

Replace the function:

```bash
cmd_fleet_sink() {
  local force=false scuttle=false
  for arg in "$@"; do
    case "$arg" in
      --force) force=true ;;
      --scuttle) scuttle=true ;;
    esac
  done

  case "$(get_role)" in
    local)
      need_flagship
      local args=""
      [[ "$force" == true ]] && args="$args --force"
      [[ "$scuttle" == true ]] && args="$args --scuttle"
      flagship_ssh "~/.local/bin/ohcommodore fleet sink $args"
      if [[ "$scuttle" == true ]]; then
        log "Removing local config..."
        rm -rf "$CONFIG_DIR"
      fi
      ;;
    commodore)
      _fleet_sink_impl "$force" "$scuttle"
      ;;
    captain)
      die "Fleet sink not available from ships"
      ;;
  esac
}

_fleet_sink_impl() {
  local force="$1"
  local scuttle="$2"

  local fleet_data
  fleet_data=$(duckdb ~/.local/ship/data.duckdb -noheader -csv "SELECT name, repo FROM fleet" 2>/dev/null || echo "")

  if [[ -z "$fleet_data" ]]; then
    echo "No ships to sink."
  else
    echo "WARNING: This will destroy all ships:"
    echo "$fleet_data" | while IFS=',' read -r name repo; do
      echo "  - $name ($repo)"
    done

    if [[ "$force" != true ]]; then
      echo ""
      printf "Type 'sink' to confirm: "
      read -r confirm
      [[ "$confirm" == "sink" ]] || die "Aborted."
    fi

    echo "$fleet_data" | while IFS=',' read -r name _repo; do
      log "Sinking $name..."
      _ship_destroy_impl "$name" >/dev/null
    done
    log "Fleet sunk."
  fi

  if [[ "$scuttle" == true ]]; then
    log "Scuttling flagship..."
    local flagship_pubkey
    flagship_pubkey=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo "")
    ssh exe.dev rm "flagship-ohcommodore" || true
    if [[ -n "$flagship_pubkey" ]]; then
      ssh exe.dev ssh-key remove "$flagship_pubkey" 2>/dev/null || true
    fi
    log "Fleet decommissioned."
  else
    echo "Flagship still running."
  fi
}
```

**Step 3: Commit**

```bash
git add ohcommodore
git commit -m "feat: add role-based routing to fleet commands"
```

---

## Task 7: Add Inbox Commands

**Files:**
- Modify: `ohcommodore` (add inbox command functions and case branch)

**Step 1: Add inbox command functions**

Add before `show_help()`:

```bash
cmd_inbox() {
  require_role commodore captain

  local subcmd="${1:-}"
  shift || true

  case "$subcmd" in
    list) _inbox_list "$@" ;;
    send) _inbox_send "$@" ;;
    read) _inbox_read "$@" ;;
    done) _inbox_done "$@" ;;
    error) _inbox_error "$@" ;;
    delete) _inbox_delete "$@" ;;
    identity) _inbox_identity ;;
    *) die "Usage: ohcommodore inbox [list|send|read|done|error|delete|identity]" ;;
  esac
}

_inbox_list() {
  local status_filter=""
  if [[ "${1:-}" == "--status" && -n "${2:-}" ]]; then
    case "$2" in
      unread|running|pending|done|error)
        status_filter="WHERE status = '$2'"
        ;;
      *)
        die "Invalid status '$2'. Must be one of: unread, running, pending, done, error"
        ;;
    esac
  fi
  duckdb ~/.local/ship/data.duckdb -box "SELECT id, status, sender, recipient, command, exit_code, created_at FROM inbox $status_filter ORDER BY created_at DESC"
}

_inbox_send() {
  [[ $# -ge 2 ]] || die "Usage: ohcommodore inbox send <recipient> <command>"
  local recipient="$1"
  local command="$2"

  if ! echo "$recipient" | grep -qE '^(captain|commodore)@.+$'; then
    die "Invalid recipient format. Use captain@<hostname> or commodore@<hostname>"
  fi

  local remote_host="${recipient#*@}"
  local id
  id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  local sender
  sender=$(_inbox_identity)
  local escaped_cmd
  escaped_cmd=$(printf '%s' "$command" | sed "s/'/''/g")

  if ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes "exedev@$remote_host" \
    "duckdb ~/.local/ship/data.duckdb \"INSERT INTO inbox (id, sender, recipient, command) VALUES ('$id', '$sender', '$recipient', '$escaped_cmd')\""; then
    echo "Message sent: $id -> $recipient"
  else
    die "Failed to send message to $recipient (host may be unreachable)"
  fi
}

_inbox_read() {
  [[ $# -ge 1 ]] || die "Usage: ohcommodore inbox read <id>"
  local escaped_id
  escaped_id=$(printf '%s' "$1" | sed "s/'/''/g")
  duckdb ~/.local/ship/data.duckdb "UPDATE inbox SET status = 'pending' WHERE id = '$escaped_id'"
  duckdb ~/.local/ship/data.duckdb -json "SELECT * FROM inbox WHERE id = '$escaped_id'"
}

_inbox_done() {
  [[ $# -ge 1 ]] || die "Usage: ohcommodore inbox done <id>"
  local escaped_id
  escaped_id=$(printf '%s' "$1" | sed "s/'/''/g")
  duckdb ~/.local/ship/data.duckdb "UPDATE inbox SET status = 'done' WHERE id = '$escaped_id'"
  echo "Marked done: $1"
}

_inbox_error() {
  [[ $# -ge 2 ]] || die "Usage: ohcommodore inbox error <id> <message>"
  local escaped_id escaped_msg
  escaped_id=$(printf '%s' "$1" | sed "s/'/''/g")
  escaped_msg=$(printf '%s' "$2" | sed "s/'/''/g")
  duckdb ~/.local/ship/data.duckdb "UPDATE inbox SET status = 'error', error = '$escaped_msg' WHERE id = '$escaped_id'"
  echo "Marked error: $1"
}

_inbox_delete() {
  [[ $# -ge 1 ]] || die "Usage: ohcommodore inbox delete <id>"
  local escaped_id
  escaped_id=$(printf '%s' "$1" | sed "s/'/''/g")
  duckdb ~/.local/ship/data.duckdb "DELETE FROM inbox WHERE id = '$escaped_id'"
  echo "Deleted: $1"
}

_inbox_identity() {
  duckdb ~/.local/ship/data.duckdb -noheader -csv "SELECT value FROM config WHERE key = 'IDENTITY'" 2>/dev/null
}
```

**Step 2: Add case branch**

Add to main case statement:

```bash
  inbox) shift; cmd_inbox "$@" ;;
```

**Step 3: Commit**

```bash
git add ohcommodore
git commit -m "feat: add inbox commands with role restriction"
```

---

## Task 8: Add Scheduler Command

**Files:**
- Modify: `ohcommodore` (add _scheduler command)

**Step 1: Add scheduler function**

Add after inbox functions:

```bash
cmd__scheduler() {
  require_role commodore captain

  local poll_interval
  poll_interval=$(duckdb ~/.local/ship/data.duckdb -noheader -csv "SELECT value FROM config WHERE key = 'POLL_INTERVAL_SEC'" 2>/dev/null || echo "10")
  local identity
  identity=$(_inbox_identity)
  [[ -n "$identity" ]] || die "No IDENTITY in config"

  log "Scheduler starting for $identity (poll: ${poll_interval}s)"

  while true; do
    local msg
    msg=$(duckdb ~/.local/ship/data.duckdb -json "
      UPDATE inbox SET status = 'running'
      WHERE id = (SELECT id FROM inbox WHERE status = 'unread' AND recipient = '$identity' LIMIT 1)
      RETURNING id, command
    " 2>/dev/null)

    if [[ -n "$msg" && "$msg" != "[]" ]]; then
      local id cmd
      id=$(echo "$msg" | jq -r '.[0].id')
      cmd=$(echo "$msg" | jq -r '.[0].command')

      local result exit_code
      result=$(eval "$cmd" 2>&1) || true
      exit_code=$?

      local escaped_result
      escaped_result=$(printf '%s' "$result" | sed "s/'/''/g")

      if [[ $exit_code -eq 0 ]]; then
        duckdb ~/.local/ship/data.duckdb "UPDATE inbox SET status='done', exit_code=$exit_code, result='$escaped_result' WHERE id='$id'"
      else
        duckdb ~/.local/ship/data.duckdb "UPDATE inbox SET status='error', exit_code=$exit_code, result='$escaped_result', error='Command failed with exit code $exit_code' WHERE id='$id'"
      fi
    fi

    sleep "$poll_interval"
  done
}
```

**Step 2: Add case branch**

```bash
  _scheduler) cmd__scheduler ;;
```

**Step 3: Commit**

```bash
git add ohcommodore
git commit -m "feat: add _scheduler command for inbox processing"
```

---

## Task 9: Update Help Text

**Files:**
- Modify: `ohcommodore` (update show_help)

**Step 1: Replace show_help function**

```bash
show_help() {
  cat <<'HELP'
ohcommodore - lightweight multi-agent control plane

USAGE:
  ohcommodore init                         Bootstrap flagship VM
  ohcommodore fleet status                 Show fleet status
  ohcommodore fleet sink [--force] [--scuttle]  Destroy ships (--scuttle: also flagship)
  ohcommodore ship create <owner/repo>     Create ship for repo
  ohcommodore ship destroy <name>          Destroy a ship
  ohcommodore ship ssh <name>              SSH into a ship
  ohcommodore inbox list [--status <s>]    List inbox messages
  ohcommodore inbox send <rcpt> <cmd>      Send command to recipient
  ohcommodore inbox read|done|error|delete <id>  Manage messages
  ohcommodore inbox identity               Show this node's identity

INTERNAL (used during VM setup):
  ohcommodore _init_commodore              Initialize as flagship
  ohcommodore _init_captain <repo>         Initialize as ship
  ohcommodore _scheduler                   Run inbox scheduler daemon
HELP
}
```

**Step 2: Commit**

```bash
git add ohcommodore
git commit -m "docs: update help text with all commands"
```

---

## Task 10: Update _init_captain for Inbox Setup

**Files:**
- Modify: `ohcommodore` (expand _init_captain to set up inbox table and identity)

**Step 1: Update cmd__init_captain**

Replace the function:

```bash
cmd__init_captain() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || die "Usage: ohcommodore _init_captain <owner/repo>"

  log "Initializing captain identity..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/identity.json" <<EOF
{"role":"captain"}
EOF

  # Set up SSH keys if provided via env
  if [[ -n "${SHIP_SSH_PRIVKEY_B64:-}" && -n "${SHIP_SSH_PUBKEY_B64:-}" ]]; then
    log "Installing SSH keys from env..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$SHIP_SSH_PRIVKEY_B64" | base64 -d > ~/.ssh/id_ed25519
    echo "$SHIP_SSH_PUBKEY_B64" | base64 -d > ~/.ssh/id_ed25519.pub
    chmod 600 ~/.ssh/id_ed25519
    chmod 644 ~/.ssh/id_ed25519.pub
  fi

  # Initialize inbox database
  log "Initializing inbox database..."
  local ship_hostname
  ship_hostname=$(hostname -f 2>/dev/null || hostname)
  mkdir -p ~/.local/ship
  duckdb ~/.local/ship/data.duckdb "
    CREATE TABLE IF NOT EXISTS config (
      key TEXT PRIMARY KEY,
      value TEXT
    );
    INSERT INTO config (key, value) VALUES ('POLL_INTERVAL_SEC', '10')
      ON CONFLICT (key) DO NOTHING;
    INSERT INTO config (key, value) VALUES ('IDENTITY', 'captain@$ship_hostname')
      ON CONFLICT (key) DO NOTHING;

    CREATE TABLE IF NOT EXISTS inbox (
      id TEXT PRIMARY KEY,
      created_at TIMESTAMP DEFAULT current_timestamp,
      status TEXT DEFAULT 'unread',
      sender TEXT,
      recipient TEXT NOT NULL,
      command TEXT,
      exit_code INTEGER,
      result TEXT,
      error TEXT
    );
  "

  # Run OS-level init
  if [[ -n "${INIT_URL:-}" ]]; then
    log "Running OS init script..."
    curl -fsSL "$INIT_URL" | GH_TOKEN="${GH_TOKEN:-}" TARGET_REPO="$repo" ROLE=captain \
      SHIP_SSH_PRIVKEY_B64="${SHIP_SSH_PRIVKEY_B64:-}" SHIP_SSH_PUBKEY_B64="${SHIP_SSH_PUBKEY_B64:-}" bash
  fi

  log "Captain initialized for $repo."
}
```

**Step 2: Similarly update cmd__init_commodore for inbox**

Update `cmd__init_commodore` to also create inbox table and config:

```bash
cmd__init_commodore() {
  log "Initializing commodore identity..."
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/identity.json" <<'EOF'
{"role":"commodore"}
EOF

  log "Initializing databases..."
  local flagship_hostname
  flagship_hostname=$(hostname -f 2>/dev/null || hostname)
  mkdir -p ~/.local/ship
  duckdb ~/.local/ship/data.duckdb "
    CREATE TABLE IF NOT EXISTS fleet (
      name TEXT PRIMARY KEY,
      repo TEXT NOT NULL,
      ssh_dest TEXT NOT NULL,
      pubkey TEXT,
      status TEXT DEFAULT 'running',
      created_at TIMESTAMP DEFAULT current_timestamp
    );

    CREATE TABLE IF NOT EXISTS config (
      key TEXT PRIMARY KEY,
      value TEXT
    );
    INSERT INTO config (key, value) VALUES ('POLL_INTERVAL_SEC', '10')
      ON CONFLICT (key) DO NOTHING;
    INSERT INTO config (key, value) VALUES ('IDENTITY', 'commodore@$flagship_hostname')
      ON CONFLICT (key) DO NOTHING;

    CREATE TABLE IF NOT EXISTS inbox (
      id TEXT PRIMARY KEY,
      created_at TIMESTAMP DEFAULT current_timestamp,
      status TEXT DEFAULT 'unread',
      sender TEXT,
      recipient TEXT NOT NULL,
      command TEXT,
      exit_code INTEGER,
      result TEXT,
      error TEXT
    );
  "

  # Run OS-level init if init.sh URL provided
  if [[ -n "${INIT_URL:-}" ]]; then
    log "Running OS init script..."
    curl -fsSL "$INIT_URL" | GH_TOKEN="${GH_TOKEN:-}" ROLE=commodore bash
  fi

  log "Commodore initialized."
}
```

**Step 3: Commit**

```bash
git add ohcommodore
git commit -m "feat: init commands set up inbox database and identity"
```

---

## Task 11: Delete flagship/bin Directory

**Files:**
- Delete: `flagship/bin/ship-create`
- Delete: `flagship/bin/ship-destroy`
- Delete: `flagship/bin/ship-list`
- Delete: `flagship/bin/` directory

**Step 1: Remove files**

```bash
rm -rf flagship/
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove flagship/bin scripts (now in ohcommodore)"
```

---

## Task 12: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update file structure section**

Replace the File Structure section:

```markdown
## File Structure

| Path | Purpose |
|------|---------|
| `ohcommodore` | Main CLI script (runs everywhere: local, flagship, ships) |
| `cloudinit/init.sh` | OS-level initialization (apt, tools, zsh, etc.) |

**Identity detection:** `~/.ohcommodore/identity.json` with `{"role":"local|commodore|captain"}`

**Local config:** `~/.ohcommodore/config.json` stores flagship SSH destination (local only)

**VM state:** `~/.local/ship/data.duckdb` stores fleet registry (flagship) and inbox (all VMs)
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for unified ohcommodore"
```

---

## Task 13: End-to-End Test

**Step 1: Test locally (dry run)**

```bash
# Check help
./ohcommodore help

# Check role detection (should be "local")
bash -c 'source ./ohcommodore; get_role'
```

**Step 2: Full integration test (requires exe.dev access)**

```bash
# Initialize flagship
GH_TOKEN=... ./ohcommodore init

# Check fleet status
./ohcommodore fleet status

# Create a ship
GH_TOKEN=... ./ohcommodore ship create owner/repo

# Check fleet again
./ohcommodore fleet status

# SSH to ship
./ohcommodore ship ssh reponame

# On ship: check inbox commands
ohcommodore inbox identity
ohcommodore inbox list

# Cleanup
./ohcommodore fleet sink --force --scuttle
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "test: verify unified ohcommodore works end-to-end"
```

---

Plan complete and saved to `docs/plans/2026-01-20-unified-ohcommodore-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
