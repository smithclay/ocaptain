---
name: voyage-plan
description: Generate a structured voyage plan for ocaptain multi-ship execution
argument-hint: "<feature-description>"
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Write", "Task"]
---

# Voyage Plan Generator

Generate a structured plan file that ocaptain ships can execute with strict task tracking.

## Process

### Step 1: Understand the Feature Request

Parse the user's feature description to identify:
- Core functionality required
- Integration points with existing code
- Testing requirements
- Success criteria

### Step 2: Explore the Codebase

Use exploration tools to understand:
1. **Project structure** - Find source directories, test directories, config files
2. **Existing patterns** - How similar features are implemented
3. **Test infrastructure** - pytest, jest, go test, etc.
4. **Build/lint tools** - Commands available in package.json, pyproject.toml, Makefile, etc.
5. **Code conventions** - Style, naming, architecture patterns

### Step 3: Identify Exit Criteria Commands

Search for verification commands in:
- `package.json` scripts (npm test, npm run lint, npm run typecheck)
- `pyproject.toml` (pytest, ruff, mypy)
- `Makefile` targets
- CI configuration (.github/workflows/)
- README instructions

The exit criteria MUST be concrete commands that return 0 on success.

### Step 4: Break Down into Tasks

Create 10-30 parallelizable tasks following these rules:
- Each task should be completable in <30 minutes
- Tasks should have clear dependencies (use "depends: N" notation)
- Independent tasks can be worked in parallel
- Each task specifies files to modify
- Each task has acceptance criteria

Task granularity guidelines:
- **Too coarse**: "Implement authentication" (needs breakdown)
- **Too fine**: "Add import statement" (merge into larger task)
- **Just right**: "Implement JWT token generation in auth/tokens.py"

### Step 5: Generate Plan File

Create the plan file at `.claude/plans/{feature-slug}-plan.md` using this exact structure:

```markdown
# Voyage Plan: {feature-name}

## Objective

{Clear 2-3 sentence description of what to build and why}

## Tasks

1. Task title (no deps)
   - Description of what to do
   - Files to modify: path/to/file.py, path/to/other.py
   - Acceptance: Specific testable outcome

2. Task title (depends: 1)
   - Description
   - Files: path/to/file.py
   - Acceptance: What success looks like

3. Task title (depends: 1)
   - Can run in parallel with task 2
   - Files: different/path.py
   - Acceptance: Criteria

{Continue for all tasks...}

## Exit Criteria

```bash
# All commands must pass for voyage completion
{command1}
{command2}
{command3}
```

## Requirements

- [ ] Specific acceptance criterion 1
- [ ] Specific acceptance criterion 2
- [ ] All tests pass
- [ ] No linting errors
```

### Step 6: Validate the Plan

Before finishing, verify:
- [ ] All dependencies form a valid DAG (no cycles)
- [ ] Tasks are numbered sequentially
- [ ] Each task has files and acceptance criteria
- [ ] Exit criteria commands exist and are runnable
- [ ] Final "Verify exit criteria" task depends on ALL other tasks

## Output

After generating the plan, report:
1. Plan file location
2. Number of tasks created
3. Parallelization potential (max parallel tasks at any level)
4. Exit criteria commands identified

## Example

For input: "Add user authentication with JWT"

Output plan might include:
- Task 1: Analyze codebase and document auth requirements (no deps)
- Task 2: Add JWT library dependency (no deps)
- Task 3: Create User model with password hashing (depends: 1)
- Task 4: Implement JWT token generation (depends: 2, 3)
- Task 5: Create login endpoint (depends: 4)
- Task 6: Create registration endpoint (depends: 3)
- Task 7: Add auth middleware (depends: 4)
- Task 8: Protect existing routes (depends: 7)
- Task 9: Write auth tests (depends: 5, 6, 7)
- Task 10: Update API documentation (depends: 5, 6)
- Task 11: Verify exit criteria (depends: ALL)
