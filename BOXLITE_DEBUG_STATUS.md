# BoxLite Provider Debug Status

## Summary

BoxLite provider is now **WORKING** with ocaptain. All issues have been fixed and the full voyage flow completes successfully.

## Issues Fixed

### 1. tailscaled Hang (FIXED)
**Problem:** BoxLite's `exec` waits for all file descriptors to close. Running `tailscaled &` caused infinite hang.

**Solution:** Use subshell + stdio redirect pattern:
```bash
(/usr/sbin/tailscaled --state=mem: --socket=/run/tailscale/tailscaled.sock --tun=userspace-networking </dev/null >/var/log/tailscaled.log 2>&1 &)
```

### 2. SSH Port 2222 (FIXED)
**Problem:** BoxLite bootstrap started sshd on port 22, but ocaptain expects port 2222.

**Solution:** Added SSH port configuration to bootstrap:
```bash
echo 'Port 2222' > /etc/ssh/sshd_config.d/ocaptain.conf
```

### 3. No systemd (FIXED)
**Problem:** `ship.py:_bootstrap_tailscale()` uses `systemctl` which doesn't exist in BoxLite VMs.

**Solution:** Added `skip_install` parameter to skip Tailscale setup for BoxLite (already done in provider bootstrap).

### 4. GitHub CLI Missing (FIXED)
**Problem:** BoxLite uses bare Ubuntu image without `gh` installed.

**Solution:** Added gh installation to bootstrap script.

### 5. SSH Key Path vs Content (FIXED)
**Problem:** `get_ssh_keypair()` returns key content, but code was passing it as a path.

**Solution:** Use explicit path `~/.config/ocaptain/id_ed25519` instead.

### 6. Connection Port for BoxLite (FIXED)
**Problem:** `get_connection()` and `wait_ready()` need to use port 2222 and explicit key for BoxLite.

**Solution:** Added BoxLite-specific handling in both functions.

### 7. apt Lock Conflict (FIXED)
**Problem:** `ship.py` runs `apt-get update && apt-get install -y tmux expect` after the BoxLite provider bootstrap. Since the bootstrap script also uses apt-get, this caused apt lock conflicts that made the command hang indefinitely.

**Solution:**
- Install tmux and expect in the BoxLite bootstrap script (alongside other packages)
- Skip the tmux/expect installation in `ship.py` for BoxLite provider

## Current Status

### What Works ✓
- BoxLite import and VM creation
- Full bootstrap script (tailscale, sshd, gh, tmux, expect, claude code) - ~2 min
- ThreadPoolExecutor usage (like voyage does)
- SSH connection via `get_connection()`
- Running commands on VM
- VM destruction
- **Full voyage flow (`ocaptain sail`)** - WORKING!

### Test Results

```
✓ Voyage voyage-4179d8ea7833 launched
  Repo: octocat/Hello-World
  Branch: voyage-4179d8ea7833
  Ships: 1
  Plan: react-hello-world
```

## Files Changed

1. `src/ocaptain/providers/boxlite.py`
   - Fixed tailscaled daemonization
   - Added SSH port 2222 configuration
   - Added gh installation
   - Added tmux and expect installation (moved from ship.py)
   - Added Tailscale directory setup
   - Added verification steps
   - Fixed `wait_ready()` to use port 2222 and correct key path

2. `src/ocaptain/ship.py`
   - Added `skip_install` parameter to `_bootstrap_tailscale()`
   - Skip Tailscale setup for BoxLite
   - Skip tmux/expect installation for BoxLite (done in provider bootstrap)

3. `src/ocaptain/provider.py`
   - Added BoxLite-specific handling in `get_connection()`

## Test Commands

```bash
# Run full voyage (WORKS!)
OCAPTAIN_PROVIDER=boxlite uv run ocaptain sail examples/generated-plans/react-hello-world/ -n 1 --no-telemetry

# Clean up
OCAPTAIN_PROVIDER=boxlite uv run ocaptain sink --all --force
```
