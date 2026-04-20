---
name: start-ticket
description: Declare an active Jira ticket for this session so the ticket-first hook lets code edits through. Accepts either a Jira key (SMASH-123) or a bare number (resolves against the default project prefix from onboarding.yaml). Run this at the start of any coding work.
disable-model-invocation: false
argument-hint: "<JIRA-KEY> | <number>"
effort: low
allowed-tools: Bash, Read, Write, mcp__sb-jira-flow__save_atlassian_config
---

# /start-ticket — Declare the Active Jira Ticket

Writes a session marker so the `require-active-ticket.sh` PreToolUse hook permits Edit/Write on code paths. Without it, the hook blocks edits to anything outside `.claude/`, `docs/`, `projects/*/docs/`, and `*.md`.

Marker layout (apexyard#41):

| Path | When the hook uses it |
|------|----------------------|
| `<ops_root>/.claude/session/tickets/<project>` | When the edit is under `<ops_root>/workspace/<project>/` AND this per-project marker exists |
| `<ops_root>/.claude/session/current-ticket` | Fallback. Always checked if the per-project marker is absent. Also used for ops-repo framework edits (where no `workspace/<name>/` prefix applies). |

Both markers live in the ops fork (gitignored).

This is the mechanical enforcement of the Pre-Build Gate in `.claude/rules/workflow-gates.md` — "do not start coding until the ticket exists".

## Process

### 1. Parse Arguments

Expected forms:

- `SMASH-42` — fully-qualified Jira key.
- `42` — bare number, resolves against the default `project_management.ticket_prefix` from `onboarding.yaml` (default `SMASH`). If the cwd maps to a managed project whose registry entry overrides `ticket_prefix`, use that instead.

If `$ARGUMENTS` is empty, stop and ask the user which ticket they're starting.

**Cross-project note:** ApexYard governs a portfolio of repos that can share one Jira project (all on `SMASH`) or span multiple (e.g. `SMASH` for product, `APEX` for ops). Whichever key the user passes wins; unambiguous Jira keys never collide.

### 2. Verify the Ticket Exists (via Jira)

Use the shared helper:

```bash
. "$ops_root/.claude/hooks/_lib-jira.sh"
if ! jira_available; then
  echo "WARN: JIRA_EMAIL / JIRA_API_TOKEN not set — writing marker without verification." >&2
else
  if ! jira_issue_exists "$JIRA_KEY"; then
    echo "ERROR: $JIRA_KEY does not exist in Jira at $(jira_issue_url "$JIRA_KEY")" >&2
    exit 1
  fi
  STATUS=$(jira_issue_state "$JIRA_KEY")
  if jira_is_closed "$JIRA_KEY"; then
    echo "WARN: $JIRA_KEY is $STATUS — do you want to resume work on a closed ticket? [y/N]"
    # wait for confirmation
  fi
fi
```

Alternative: if the Atlassian MCP `getJiraIssue` is available, prefer that — it handles auth centrally and produces typed output.

Fetch the summary (title), status, and type to populate the marker.

### 3. Derive a Branch Suggestion

From the issue summary and key, generate: `<type>/<JIRA-KEY>-<slug>` where:

- `<type>` is guessed from the issue type or summary prefix:
  - Bug → `fix`
  - Story / Feature → `feature`
  - Task / Chore → `chore` or `refactor` depending on summary keywords
  - Default → `feature`
- `<JIRA-KEY>` is the unmodified Jira key (e.g. `SMASH-42`)
- `<slug>` = lowercase summary, kebab-case, max 40 chars, stopwords trimmed from the edges

Match the convention in `.claude/rules/git-conventions.md`.

### 4. Resolve the target marker

#### 4a. Locate the ops root

The ops root contains BOTH `onboarding.yaml` and `apexyard.projects.yaml`. Walk up from CWD:

```bash
ops_root=""
r=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
while [ -n "$r" ] && [ "$r" != "/" ]; do
  if [ -f "$r/onboarding.yaml" ] && [ -f "$r/apexyard.projects.yaml" ]; then
    ops_root="$r"
    break
  fi
  r=$(dirname "$r")
done
```

If not found, tell the user and stop.

#### 4b. Determine which project (if any) this ticket belongs to

Since tickets live in Jira (not GitHub), the project/registry mapping uses `ticket_prefix`:

```bash
PREFIX=$(echo "$JIRA_KEY" | cut -d'-' -f1)  # e.g. SMASH
if command -v yq >/dev/null 2>&1; then
  project=$(yq eval ".projects[] | select(.ticket_prefix == \"${PREFIX}\") | .name" "$ops_root/apexyard.projects.yaml" | head -1)
else
  # Greppy fallback — finds the `name:` whose `ticket_prefix:` in the same entry matches.
  project=$(awk -v p="$PREFIX" '
    function unquote(s) { gsub(/^["\x27]|["\x27]$/, "", s); return s }
    /^[[:space:]]*- name:/ { name = unquote($3) }
    /^[[:space:]]*ticket_prefix:/ { if (unquote($2) == p) { print name; exit } }
  ' "$ops_root/apexyard.projects.yaml")
fi
```

If exactly one project entry uses that prefix, `$project` is that name. If zero or multiple, prefer the default (ops-level fallback marker).

#### 4c. Pick the marker path

```bash
if [ -n "$project" ] && [ -d "$ops_root/workspace/$project" ]; then
  marker="$ops_root/.claude/session/tickets/$project"
else
  marker="$ops_root/.claude/session/current-ticket"
fi
mkdir -p "$(dirname "$marker")"
```

### 5. Write the marker (v2 format)

```
tracker=jira
key=<JIRA-KEY>
title=<summary>
url=<JIRA_BASE_URL>/browse/<JIRA-KEY>
status_at_start=<status>
suggested_branch=<branch>
started_at=<ISO-8601>
```

Back-compat note: the hooks also read legacy `repo=` / `number=` fields, so pre-existing markers from the GitHub era continue to unblock edits until they're replaced.

### 6. Confirm to the User

```
Active ticket: <JIRA-KEY> — <summary>
Status:        <status>
Marker:        <marker>  (per-project / ops fallback)
Suggested branch: <branch>
```

Do NOT create the branch automatically. The user may already be on one.

## Notes

- `.claude/session/` (including `.claude/session/tickets/`) is gitignored.
- Running `/start-ticket` again overwrites the marker at whichever path resolved in step 4c.
- To clear a specific project's marker: `rm <ops_root>/.claude/session/tickets/<project>`.
- To clear the ops-level fallback: `rm <ops_root>/.claude/session/current-ticket`.
- Exempt paths (`.claude/`, `docs/`, `projects/*/docs/`, any `*.md`) don't need a ticket.
- **Credentials**: the Jira existence check uses `JIRA_EMAIL` + `JIRA_API_TOKEN` from the environment. Get a token at https://id.atlassian.com/manage-profile/security/api-tokens and export both in your shell profile.
