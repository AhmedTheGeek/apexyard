# Git Conventions

## Branch Naming

Format: `{type}/{JIRA-KEY}-{description}`

Examples:

- `feature/SMASH-123-add-auth`
- `fix/SMASH-45-login-bug`
- `docs/SMASH-99-update-readme`

**Types**: `feature`, `fix`, `refactor`, `chore`, `docs`, `test`, `spike`, `ci`, `build`, `perf`

The `JIRA-KEY` is a standard Jira issue key: 2–10 uppercase chars + dash + digits. The default project prefix comes from `onboarding.yaml` (`project_management.ticket_prefix`, default `SMASH`); per-repo overrides live in `apexyard.projects.yaml`.

## PR Title Format

Must match: `type(JIRA-KEY): description` or `type(JIRA-KEY)!: description` (breaking change)

Regex: `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\([A-Z]{2,10}-[0-9]+\)!?:`

- One Jira key per PR title — multi-ticket titles like `fix(SMASH-1,2,3):` are rejected
- Breaking changes use `!` before the colon: `feat(SMASH-58)!: remove deprecated v1 endpoints`

## Commit Message Format

```
type: subject
type!: subject (breaking change)
type(scope)!: subject (breaking change with scope)

- Detailed change 1
- Detailed change 2

Closes SMASH-123
```

Jira smart-commit syntax is the bare key (no `#` sigil). `Closes`, `Fixes`, `Resolves`, and `Refs` are all recognised.

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `perf`

## File Staging

**NEVER** use `git add -A`, `git add .`, or `git add --all`. Always add specific files:

```bash
git add src/specific-file.ts
```

This is enforced by the `block-git-add-all.sh` hook.

## No Direct Main

Every change must go through a PR. Zero exceptions. No commits directly to `main`/`master`. Enforced by the `block-main-push.sh` hook.

## No Hardcoded Secrets

No API keys, passwords, tokens, or credentials in code. Use environment variables. Patterns to avoid:

- `api_key=`, `password=`, `secret=`, `token=`
- Cloud account IDs and ARNs
- Database connection strings
- Private keys or certificates

Enforced by the `check-secrets.sh` hook.
