# Task Creation Issue

## Problem

Claude Code ships ignore task creation instructions and proceed directly to doing work, even when:
- Instructions are passed as a system prompt (via `--system-prompt-file`)
- The prompt explicitly says "Run TaskList() NOW" as the FIRST step
- Rules state "No work without a task"

## Observed Behavior

1. Ship starts with system prompt containing task instructions
2. Claude immediately begins coding work (e.g., `npm install`, creating files)
3. No TaskCreate() or TaskUpdate() calls are made
4. Task directory remains empty
5. Voyage status stays in "planning" forever

## What We've Fixed

- **Token handling**: OAuth token passed via env var, not settings.json
- **Onboarding**: Skip with `{"hasCompletedOnboarding":true}` in ~/.claude.json
- **TTY issue**: Use `script -q` command to provide pseudo-TTY (fixes CLI hang)
- **Prompt quoting**: Use `--system-prompt-file` instead of inline prompt
- **Simplified prompt**: Reduced from 1004 words to 180 words

## What Doesn't Work

Even with a 180-word prompt that says:
```
## FIRST: Check Tasks

Run TaskList() NOW. Then:

**No tasks?** You're the planner:
1. Read plan.md if it exists
2. TaskCreate() for each task
...
```

Claude ignores this and jumps to implementation.

## Root Cause Hypothesis

Claude prioritizes "getting the job done" over following process instructions. The objective ("Create a React app") is more salient than the meta-instructions ("use tasks to track work").

## Potential Solutions

### 1. Pre-create tasks in CLI (Recommended)

Instead of relying on Claude to create tasks, have `ocaptain sail` create them:
- Parse plan.md in the CLI
- Create tasks via the task API before ships start
- Ships only need to claim and complete tasks

### 2. Hook enforcement

Create a Claude Code hook that blocks file writes unless a task is in_progress:
- Pre-tool hook checks for active task
- Returns error message if no task claimed
- Forces Claude to use task system

### 3. Different prompt structure

Try making task usage the ONLY path forward:
- Don't mention the objective in the system prompt
- First user message: "Run TaskList() and claim a task"
- Objective only visible after reading plan.md

### 4. Resume-based approach

Instead of starting fresh:
- Create a session with tasks already created
- Resume that session on each ship
- Claude sees existing task context

## Current Status

The infrastructure is in place but task creation is unreliable. The plan-based voyage system works for:
- Plan file generation (`/voyage-plan`)
- Plan validation (`/voyage-validate`)
- Plan copying to ships
- Exit criteria verification script

But ships don't follow the task protocol.

## Next Steps

1. Implement option 1 (pre-create tasks in CLI)
2. Or implement hook enforcement
3. Or accept manual task creation and focus on task claiming/completion
