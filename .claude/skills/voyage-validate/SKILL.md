---
name: voyage-validate
description: Validate a voyage plan file before execution
argument-hint: "<plan-path>"
allowed-tools: ["Read", "Bash", "Grep", "Glob"]
---

# Voyage Plan Validator

Validate a voyage plan file is well-formed before launching with `ocaptain sail --plan`.

## Process

### Step 1: Read the Plan File

Read the plan file from the provided path (or `.claude/plans/*.md` if searching).

### Step 2: Validate Required Sections

Check that ALL of these sections exist:

| Section | Required Content |
|---------|------------------|
| `## Objective` | 1+ sentences describing the goal |
| `## Tasks` | Numbered task list |
| `## Exit Criteria` | Code block with shell commands |
| `## Requirements` | Checkbox list of acceptance criteria |

**Report error if any section is missing.**

### Step 3: Validate Task Structure

For each numbered task, verify:

1. **Has title** - Text after number
2. **Has description** - Indented content under title
3. **Has files** - Line starting with "Files:" or "Files to modify:"
4. **Has acceptance** - Line starting with "Acceptance:" or acceptance criteria
5. **Has valid dependencies** - "(depends: N, M)" or "(no deps)" notation

Example valid task:
```markdown
3. Implement JWT token generation (depends: 1, 2)
   - Create token generation and verification functions
   - Files: src/auth/tokens.py, src/auth/__init__.py
   - Acceptance: Can generate and verify valid JWT tokens
```

**Report which tasks are missing required fields.**

### Step 4: Validate Dependency Graph

Build the dependency graph and check:

1. **All referenced tasks exist** - If task 5 depends on task 10, task 10 must exist
2. **No circular dependencies** - Detect cycles in the DAG
3. **Final task depends on ALL others** - Last task should be exit criteria verification

Algorithm for cycle detection:
```
for each task:
  visited = set()
  if has_cycle(task, visited):
    report cycle
```

**Report any invalid dependencies or cycles.**

### Step 5: Validate Exit Criteria

Extract commands from the Exit Criteria code block:

1. **Parse the code block** - Extract each line as a command
2. **Check commands exist** - For each command, verify:
   - If `npm ...`: Check package.json exists
   - If `pytest ...`: Check pyproject.toml or pytest.ini exists
   - If `make ...`: Check Makefile exists
   - Generic: Check the binary exists (`which {binary}`)

**Report commands that may not work.**

### Step 6: Generate Report

Output a validation report:

```
## Validation Report: {plan-file}

### Sections
- [x] Objective: Found
- [x] Tasks: Found (N tasks)
- [x] Exit Criteria: Found
- [x] Requirements: Found

### Tasks
- [x] All tasks have titles
- [x] All tasks have descriptions
- [x] All tasks have files specified
- [x] All tasks have acceptance criteria
- [ ] Task 4 missing "Files:" line

### Dependencies
- [x] All dependencies reference valid tasks
- [x] No circular dependencies
- [x] Final task blocks on all others

### Exit Criteria
- [x] Commands parsed: npm test, npm run lint
- [x] package.json found - npm commands valid
- [ ] Warning: 'npm run typecheck' not in package.json scripts

### Result: VALID (with warnings) / INVALID
```

## Validation Errors vs Warnings

**Errors (INVALID):**
- Missing required sections
- Tasks without titles
- Circular dependencies
- References to non-existent tasks

**Warnings (VALID with warnings):**
- Tasks missing optional fields (files, acceptance)
- Exit criteria commands that might not exist
- Very long task descriptions
- Unusual dependency patterns

## Usage

```bash
# Validate a specific plan
/voyage-validate .claude/plans/my-feature-plan.md

# Find and validate plans
/voyage-validate  # validates most recent plan in .claude/plans/
```
