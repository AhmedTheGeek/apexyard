---
name: projects
description: List all active projects under ApexYard management with their status, branch, open PRs, and open issue counts. Use when you need a portfolio-level view.
allowed-tools: Bash, Read, Grep, Glob
---

# /projects — List Managed Projects

Show every project ApexYard is managing, with a one-line health snapshot. Reads `apexyard.projects.yaml` at the root of the ops repo (your fork of apexyard) and iterates the registry.

## Usage

```
/projects
/projects --status active
/projects --json
```

## Behaviour

Read `apexyard.projects.yaml`:

```yaml
version: 1
projects:
  - name: example-app
    repo: your-org/example-app
    workspace: workspace/example-app
    docs: projects/example-app
    status: active
    roles: [tech-lead, backend-engineer]
```

For each project, gather:

```bash
# If a local workspace clone exists, use it for git data
if [ -d "{workspace}" ]; then
  BRANCH=$(git -C {workspace} rev-parse --abbrev-ref HEAD)
  LAST=$(git -C {workspace} log -1 --format='%h %ar %s')
  DIRTY=$(git -C {workspace} status --porcelain | wc -l | tr -d ' ')
else
  BRANCH="(not cloned)"
  LAST="-"
  DIRTY="-"
fi

# GitHub is the source of truth for PRs
PRS=$(gh -R {repo} pr list --state open --json number --jq 'length')

# Jira is the source of truth for tickets — query JQL per project key
PREFIX={ticket_prefix}  # from the registry entry (or the global default)
TICKETS=$(curl -sf -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" -H "Accept: application/json" \
  --data-urlencode "jql=project = ${PREFIX} AND statusCategory != Done" \
  --data-urlencode "fields=summary" \
  --data-urlencode "maxResults=0" \
  --get "${JIRA_BASE_URL:-https://awesomemotive.atlassian.net}/rest/api/3/search" \
  | jq -r '.total // 0')
```

If `apexyard.projects.yaml` doesn't exist at the ops-repo root, print a clear error pointing the user at `apexyard.projects.yaml.example` and `docs/multi-project.md` for the setup guide.

## Output format

A markdown table:

```markdown
| Project | Jira Key | Status | Branch | PRs | Tickets | Last Commit | Dirty |
|---------|----------|--------|--------|-----|---------|-------------|-------|
| example-app | SMASH | active | main | 3 | 12 | 2h ago — fix(...) | 0 |
| billing-api | SMASH | handover | feature/SMASH-4 | 1 | 8 | 1d ago — feat(...) | 2 |
| marketing-site | APEX | paused | main | 0 | 1 | 30d ago — chore(...) | 0 |
```

After the table, a summary line:

```
3 projects · 4 open PRs · 21 open Jira tickets · 1 dirty workspace
```

And, if relevant, flag rows that need attention:

```
⚠ marketing-site: last commit 30 days ago (paused or stale?)
⚠ billing-api: 2 uncommitted files in workspace
```

## Filters

| Flag | Effect |
|------|--------|
| `--status active` | Only show projects with `status: active` |
| `--status handover` | Only show projects mid-handover |
| `--status paused` | Only show paused projects |
| `--status archived` | Only show archived projects |
| `--json` | Emit machine-readable JSON instead of a table |

## Errors and edge cases

| Condition | Behaviour |
|-----------|-----------|
| No `apexyard.projects.yaml` at the ops-repo root | Print a clear error and a sample registry to copy |
| Project listed but workspace path missing | Show row with `(not cloned)` — don't fail |
| `gh` not authenticated | Show row with `?` for PRs/issues — don't fail |
| `repo` field looks invalid | Skip with a warning, continue with the rest |

## Rules

1. **Registry-driven** — the registry is the source of truth; no discovery fallback
2. **Source of truth for PRs = GitHub**, **tickets = Jira** — don't mix them. Branch state comes from the local workspace.
3. **Don't silently fail on a missing project** — show the row, mark the gap
4. **Sort by status then name** — active first, then handover, then paused, then archived
5. **Never modify the registry from this skill** — read-only
6. **Per-project Jira key** — `ticket_prefix` from the registry entry takes priority over the global `project_management.ticket_prefix` in `onboarding.yaml`

## Related skills

- `/inbox` — same registry, but filtered to "needs your attention"
- `/status` — per-project deep dive (current branch, recent commits)
- `/tasks` — actionable list with URLs
- `/handover` — onboard a new repo into the registry
