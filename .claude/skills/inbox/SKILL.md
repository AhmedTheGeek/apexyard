---
name: inbox
description: Show every item across managed projects that needs the user's attention — PRs to review, issues assigned to them, comments to respond to, blockers. Use to triage the day.
allowed-tools: Bash, Read, Grep, Glob
---

# /inbox — Items Needing Your Attention

Aggregates everything that's currently waiting on **you** across the projects ApexYard manages. Designed to be the first thing you run in a session.

## Usage

```
/inbox
/inbox --me octocat
/inbox --since 24h
```

## Scope

`/inbox` iterates every project in `apexyard.projects.yaml` at the root of your ops repo (your fork of apexyard). If the registry doesn't exist, print a clear error pointing at `docs/multi-project.md`.

## What goes in the inbox

The inbox is grouped by section. Empty sections are omitted.

### 1. PRs awaiting your review

```bash
gh pr list \
  --search "is:open is:pr review-requested:@me" \
  --json number,title,url,headRepository,updatedAt,author \
  --limit 50
```

Run this per `repo:` from the registry (or use `--search "user:your-org"` if you have an org).

### 2. PRs you authored that have changes requested

```bash
gh pr list \
  --search "is:open is:pr author:@me review:changes_requested" \
  --json number,title,url
```

These are blocking **you**, not your reviewers — they're your inbox.

### 3. PRs you authored that are approved and ready to merge

```bash
gh pr list \
  --search "is:open is:pr author:@me review:approved" \
  --json number,title,url,mergeable,mergeStateStatus
```

Filter to ones where `mergeStateStatus` is `CLEAN` — those are ready to merge right now.

### 4. Jira issues assigned to you

Query Jira per registered project (using the project's `ticket_prefix`, defaulting to the global `project_management.ticket_prefix` from `onboarding.yaml`):

```bash
# Tickets assigned to you, excluding Done/Cancelled
curl -sf -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" -H "Accept: application/json" \
  --data-urlencode "jql=project = ${PREFIX} AND assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC" \
  --data-urlencode "fields=summary,status,priority,updated" \
  --data-urlencode "maxResults=50" \
  --get "${JIRA_BASE_URL:-https://awesomemotive.atlassian.net}/rest/api/3/search"
```

Group by project / Jira project key. If credentials aren't available, surface one-line warning and continue with the PR sections.

### 5. Jira issues you reported that are still open

```
jql=project = ${PREFIX} AND reporter = currentUser() AND statusCategory != Done ORDER BY updated DESC
```

Show newest first. This surfaces tickets you filed but haven't been actioned on yet.

### 6. Mentions in Jira comments / descriptions

```
jql=project = ${PREFIX} AND text ~ "currentUser()" AND statusCategory != Done ORDER BY updated DESC
```

Jira doesn't have a native `@me` operator — `text ~` matches free-text fields. Fall back to `assignee = currentUser() OR reporter = currentUser()` if text-search doesn't surface what you expect.

### 7. PRs failing CI on a branch you authored

```bash
gh pr list \
  --search "is:open is:pr author:@me" \
  --json number,title,url,statusCheckRollup
```

Filter client-side to those where any check is `FAILURE`.

### 8. Blocking Jira tickets

```
jql=project = ${PREFIX} AND labels in (blocked, blocker) AND statusCategory != Done
```

Run per registered project.

## Output format

Group everything under headings, project-prefixed:

```
INBOX — 2026-04-06 09:14
=========================

🔴 PRs awaiting your review (3)
  · example-app#42  Add export to CSV         updated 1h ago   https://…
  · billing-api#8   Fix invoice rounding      updated 3h ago   https://…
  · marketing#12    Hero copy refresh         updated 1d ago   https://…

🟡 Your PRs with changes requested (1)
  · example-app#39  Refactor session store    Code Reviewer requested changes   https://…

🟢 Your PRs ready to merge (1)
  · example-app#41  Add health endpoint       2 approvals · CI green            https://…

📬 Jira tickets assigned to you (4)
  · SMASH-117   [Bug] Login fails on Safari       Highest   In Progress   https://…/browse/SMASH-117
  · SMASH-22    Multi-currency support            High      To Do         https://…/browse/SMASH-22
  · …

💬 Jira tickets you reported, still open (2)
  · SMASH-98    Waiting on triage                 Medium    https://…/browse/SMASH-98
  · SMASH-5     Designer added a comment          Low       https://…/browse/SMASH-5

🚨 PRs with failing CI (1)
  · example-app#42   lint job failed                    https://…

🛑 Blocked Jira tickets (1)
  · SMASH-19    Waiting on API key from vendor     https://…/browse/SMASH-19

Summary: 12 items · 3 PRs to review · 1 ready to merge · 1 blocking CI failure
```

If everything is empty:

```
✨ Inbox zero. Nothing waiting on you across {N} projects.
```

## Filters

| Flag | Effect |
|------|--------|
| `--me <user>` | Run as if `<user>` is the current user (default: `@me`) |
| `--since <duration>` | Only items updated in the window (e.g. `24h`, `7d`) |
| `--project <name>` | Limit to one project from the registry |
| `--no-mentions` | Hide the mentions section |

## Rules

1. **Read-only** — never close, comment, or assign anything from this skill
2. **Always sort by recency within each section** — newest updates first
3. **Registry-scoped** — only projects listed in `apexyard.projects.yaml` count; never shell out to "all repos in the org"
4. **Skip empty sections** — don't print headers with `(0)`
5. **Never error on a single source** — if Jira is unreachable, surface a warning once and continue with GitHub data (and vice versa)
6. **Always include URLs** — every row needs a clickable link (Jira `.../browse/<KEY>` or GitHub PR URL)
7. **No noise** — items where you have no possible action shouldn't appear (e.g. PRs you've already approved)
8. **Hybrid source** — tickets from Jira, PRs from GitHub. Don't conflate them.

## Related skills

- `/tasks` — same data but flattened into a single ordered TODO list
- `/status` — current project's git/CI snapshot
- `/projects` — portfolio-level health snapshot
