# Voyage Plan Format

This document describes the structured plan file format used by ocaptain for multi-ship execution.

## Overview

Voyage plans are Markdown files that define:
- What to build (Objective)
- How to build it (Tasks with dependencies)
- How to verify it's done (Exit Criteria)
- What success looks like (Requirements)

Plans enable ships to work autonomously while maintaining coordination through the task system.

## File Location

Plans should be stored in `.claude/plans/` with descriptive names:
```
.claude/plans/user-auth-plan.md
.claude/plans/api-refactor-plan.md
.claude/plans/performance-optimization-plan.md
```

## Required Sections

### 1. Objective

A clear 2-3 sentence description of what to build and why.

```markdown
## Objective

Add JWT-based user authentication to the API. Users should be able to register,
login, and access protected endpoints. This enables the frontend team to implement
user-specific features.
```

### 2. Tasks

Numbered list of tasks with dependencies, files, and acceptance criteria.

```markdown
## Tasks

1. Analyze codebase and document auth requirements (no deps)
   - Review existing API structure and identify integration points
   - Document which endpoints need protection
   - Files: docs/auth-requirements.md
   - Acceptance: Requirements document created and reviewed

2. Add authentication dependencies (no deps)
   - Add PyJWT and passlib to requirements
   - Files: requirements.txt, pyproject.toml
   - Acceptance: Dependencies install without conflicts

3. Create User model with password hashing (depends: 1)
   - Implement User model with secure password storage
   - Add database migration
   - Files: src/models/user.py, migrations/
   - Acceptance: Can create users with hashed passwords

4. Implement JWT token generation (depends: 2, 3)
   - Create token creation and verification utilities
   - Configure token expiration and secrets
   - Files: src/auth/tokens.py, src/config.py
   - Acceptance: Can generate and verify valid tokens

5. Verify exit criteria (depends: ALL)
   - Run all verification commands
   - Fix any failing tests or lint errors
   - Acceptance: All exit criteria commands pass
```

#### Task Dependency Notation

- `(no deps)` - Task can start immediately
- `(depends: 1)` - Task requires task 1 to complete first
- `(depends: 1, 3)` - Task requires tasks 1 AND 3 to complete first
- `(depends: ALL)` - Task requires all other tasks to complete (use for final verification)

#### Task Components

Each task should include:

| Component | Required | Description |
|-----------|----------|-------------|
| Title | Yes | Brief imperative description (e.g., "Implement JWT tokens") |
| Description | Yes | 1-3 lines explaining what to do |
| Files | Recommended | Paths to files that will be modified |
| Acceptance | Recommended | Specific testable outcome |

### 3. Exit Criteria

Shell commands that must all pass for the voyage to be considered complete.

```markdown
## Exit Criteria

```bash
# All commands must return exit code 0
pytest tests/ -v
ruff check src/
mypy src/
```
```

Common exit criteria:
- **Python**: `pytest`, `ruff check`, `mypy`, `black --check`
- **JavaScript/TypeScript**: `npm test`, `npm run lint`, `npm run typecheck`
- **Go**: `go test ./...`, `go vet ./...`, `golangci-lint run`
- **Rust**: `cargo test`, `cargo clippy`, `cargo fmt --check`

### 4. Requirements

Checkbox list of acceptance criteria for the overall feature.

```markdown
## Requirements

- [ ] Users can register with email and password
- [ ] Users can login and receive a JWT token
- [ ] Protected endpoints reject requests without valid tokens
- [ ] Tokens expire after configured duration
- [ ] All tests pass
- [ ] No linting errors
- [ ] API documentation updated
```

## Complete Example

```markdown
# Voyage Plan: user-authentication

## Objective

Add JWT-based user authentication to enable secure access to protected API
endpoints. Users should be able to register, login, and use tokens to access
their personal data.

## Tasks

1. Analyze codebase and identify auth integration points (no deps)
   - Review existing API routes and middleware structure
   - Document which endpoints need protection
   - Files: docs/auth-integration.md
   - Acceptance: Integration plan documented

2. Add JWT and password hashing dependencies (no deps)
   - Add PyJWT>=2.0 and passlib[bcrypt] to requirements
   - Files: requirements.txt
   - Acceptance: pip install succeeds

3. Create User model (depends: 1)
   - Implement User SQLAlchemy model with password hashing
   - Add migration for users table
   - Files: src/models/user.py, src/models/__init__.py, migrations/
   - Acceptance: Can create and query users

4. Implement JWT utilities (depends: 2)
   - Create token generation and verification functions
   - Add JWT secret to config
   - Files: src/auth/jwt.py, src/config.py
   - Acceptance: Can generate and verify tokens

5. Create registration endpoint (depends: 3)
   - POST /auth/register creates new user
   - Validate email format and password strength
   - Files: src/routes/auth.py
   - Acceptance: Can register new users via API

6. Create login endpoint (depends: 3, 4)
   - POST /auth/login returns JWT token
   - Verify password and return token on success
   - Files: src/routes/auth.py
   - Acceptance: Can login and receive token

7. Add auth middleware (depends: 4)
   - Create middleware that validates JWT tokens
   - Extract user from token and add to request context
   - Files: src/middleware/auth.py
   - Acceptance: Middleware correctly validates tokens

8. Protect existing endpoints (depends: 7)
   - Apply auth middleware to endpoints that need protection
   - Update route decorators
   - Files: src/routes/users.py, src/routes/data.py
   - Acceptance: Protected endpoints reject invalid tokens

9. Write authentication tests (depends: 5, 6, 7, 8)
   - Test registration, login, token validation
   - Test protected endpoint access
   - Files: tests/test_auth.py
   - Acceptance: All auth tests pass

10. Update API documentation (depends: 5, 6)
    - Document new auth endpoints
    - Document authentication requirements
    - Files: docs/api.md
    - Acceptance: Docs cover all auth endpoints

11. Verify exit criteria (depends: ALL)
    - Run all verification commands
    - Fix any failures
    - Acceptance: All commands pass

## Exit Criteria

```bash
pytest tests/ -v --tb=short
ruff check src/
mypy src/ --ignore-missing-imports
```

## Requirements

- [ ] Users can register with email and password
- [ ] Users can login and receive a JWT token
- [ ] JWT tokens expire after 24 hours
- [ ] Protected endpoints return 401 without valid token
- [ ] Protected endpoints work with valid token
- [ ] Password is never stored in plaintext
- [ ] All tests pass
- [ ] No linting errors
- [ ] Code passes type checking
```

## Using Plans with ocaptain

### Generate a Plan

Use the `/voyage-plan` skill to generate a plan from a feature description:

```bash
claude
> /voyage-plan "Add user authentication with JWT"
```

### Validate a Plan

Use the `/voyage-validate` skill to check a plan before launching:

```bash
claude
> /voyage-validate .claude/plans/user-auth-plan.md
```

### Launch a Voyage

For distributed execution across multiple ships:

```bash
ocaptain sail --plan .claude/plans/user-auth-plan.md -r my-org/my-repo
```

The plan file is copied to the storage VM. Ships execute a simple loop:

1. **TaskList()** - Check what exists
2. **No tasks?** Create them from plan.md, then claim one
3. **Tasks exist?** Claim a pending unblocked task
4. **Work loop:** claim → implement → complete → repeat
5. **Before exit:** Run verify.sh if it exists, fix failures

## Best Practices

### Task Granularity

- Each task should be completable in under 30 minutes
- Tasks should be specific enough to implement without ambiguity
- Tasks should be independent enough to allow parallel execution

### Dependencies

- Minimize dependencies to maximize parallelism
- Tasks that touch the same files should have dependencies
- Use `(no deps)` for tasks that can start immediately
- Always have a final task that depends on ALL for verification

### Exit Criteria

- Exit criteria should be fast to run (< 5 minutes total)
- Include all automated checks: tests, linting, type checking
- Don't include manual verification steps

### Requirements

- Requirements should be testable/verifiable
- Include both functional and non-functional requirements
- Keep the list focused on the feature being built
