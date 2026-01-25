# Zellij Interactive Ships Design

**Date:** 2026-01-25
**Status:** Approved

## Problem

Ships running Claude in print mode (`claude -p`) don't have access to the built-in Task* tools (TaskCreate, TaskUpdate, TaskGet, TaskList). These tools only exist in interactive mode. This limits coordination capabilities.

## Goals

1. Enable Task* tools on ships by running Claude interactively
2. Provide observability - attach to running ships, watch Claude work in real-time

## Architecture

Hub-and-spoke model with zellij on storage VM:

```
┌─────────────────────────────────────────────────┐
│  Storage VM (Bridge)                            │
│  ┌─────────────────────────────────────────┐    │
│  │ zellij session: voyage-{id}             │    │
│  │ ┌─────────┐ ┌─────────┐ ┌─────────┐     │    │
│  │ │ ship-0  │ │ ship-1  │ │ ship-2  │     │    │
│  │ │ (pane)  │ │ (pane)  │ │ (pane)  │     │    │
│  │ │   ↓     │ │   ↓     │ │   ↓     │     │    │
│  │ │ssh→VM0  │ │ssh→VM1  │ │ssh→VM2  │     │    │
│  │ └─────────┘ └─────────┘ └─────────┘     │    │
│  └─────────────────────────────────────────┘    │
│  Shared: ~/voyage/, ~/.claude/tasks/{id}/       │
└─────────────────────────────────────────────────┘
```

- Storage VM runs a zellij session with one pane per ship
- Each pane SSHs to its ship and runs Claude interactively
- Human attaches to observe all ships from one place
- Ships run autonomously; human observes but doesn't interfere

## SSH Reliability

Running Claude via SSH has risks (network blips kill the process). Mitigations:

**SSH hardening:**
```bash
Host ship-*
    ServerAliveInterval 15
    ServerAliveCountMax 3
    TCPKeepAlive yes
    ConnectionAttempts 3
    ConnectTimeout 10
```

**Graceful degradation:**
- Ships commit frequently; work survives session death
- Dead ship's tasks remain `in_progress`, can be reset
- Other ships continue working unaffected

**Accepted tradeoff:** For voyages of a few hours, this is acceptable. Multi-day voyages may need per-ship zellij (future enhancement).

## Bootstrap Flow

**Current:**
1. Provision storage VM
2. Provision ship VMs in parallel
3. Each ship mounts storage, runs `claude -p` with nohup

**New:**
1. Provision storage VM
   - Install zellij
2. Provision ship VMs in parallel
   - Mount storage via SSHFS (unchanged)
   - Write ship identity (unchanged)
   - Configure Claude Code (unchanged)
   - **No start script** - ship waits
3. Storage creates zellij session and launches ships
   - Generate layout.kdl
   - Start zellij with layout (detached)
   - Each pane SSHs to its ship and runs Claude

## Launching Claude in Panes

Each pane runs:
```bash
ssh ship-{i} 'cd ~/voyage/workspace && \
  CLAUDE_CODE_OAUTH_TOKEN="..." \
  CLAUDE_CODE_TASK_LIST_ID="..." \
  claude --dangerously-skip-permissions \
         --system-prompt-file ~/voyage/prompt.md \
         "Begin" \
  2>&1 | tee -a ~/voyage/logs/ship-{i}.log'
```

Key differences from print mode:
- No `-p` flag = interactive mode = Task* tools available
- Claude runs until it decides to stop
- Output logged to file via tee

## Zellij Layout

Generated dynamically per voyage:

```kdl
layout {
    tab name="voyage-{id}" {
        pane split_direction="vertical" {
            pane name="ship-0" command="ssh" {
                args "ship-0" "cd ~/voyage/workspace && ..."
            }
            pane name="ship-1" command="ssh" {
                args "ship-1" "cd ~/voyage/workspace && ..."
            }
        }
    }
}
```

Pane arrangement:
- 2-3 ships: vertical split
- 4+ ships: grid layout (2 columns)

## CLI Changes

| Command | Behavior |
|---------|----------|
| `ocaptain sail` | Creates zellij session on storage after ships provisioned |
| `ocaptain shell <voyage> [ship]` | Attaches to zellij session; optionally focuses specific pane |
| `ocaptain logs <voyage>` | Unchanged - reads log files |
| `ocaptain status <voyage>` | Unchanged - reads task files |
| `ocaptain sink <voyage>` | Kills zellij session, then destroys VMs |
| `ocaptain resume <voyage>` | Adds new panes to existing zellij session |

## Error Handling

| Scenario | Result | Recovery |
|----------|--------|----------|
| SSH to ship drops | Pane shows disconnect, Claude dies | Reset stale tasks, resume |
| Ship completes tasks | Pane shows exit, Stop hook fires | Other ships continue |
| Storage VM dies | All sessions lost | Resume with new storage, git work survives |
| Claude waits for input | Pane shows question | Human attaches and answers (rare) |

## Implementation

**Files to modify:**

| File | Changes |
|------|---------|
| `ship.py` | Remove start script + nohup launch from `bootstrap_ship()` |
| `voyage.py` | Add `launch_fleet()` to create zellij session after ships ready |
| `cli.py` | Update `shell` to attach to zellij, `sink` to kill session first |
| `providers/exedev.py` | Install zellij on storage VM during bootstrap |

**New files:**

| File | Purpose |
|------|---------|
| `zellij.py` | Generate layout.kdl, manage sessions (create/attach/delete) |

## Testing

1. `ocaptain sail` with 2 ships - verify zellij session created
2. `ocaptain shell` - verify attachment shows both panes
3. Verify Task* tools work (ship successfully uses TaskList)
4. Kill SSH connection - verify other ships continue working
