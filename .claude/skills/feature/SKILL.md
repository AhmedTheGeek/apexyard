---
name: feature
description: Create a structured feature request ticket in Jira with user story, acceptance criteria, and design notes. Use when proposing a new user-facing feature.
argument-hint: "<short title of the feature>"
allowed-tools: Bash, Read, Write, mcp__sb-jira-flow__create_ticket, mcp__sb-jira-flow__validate_ticket_title, mcp__sb-jira-flow__save_atlassian_config
---

# /feature — Create a Feature Request Ticket (Jira)

Creates a structured Jira ticket for a new feature with a user story, acceptance criteria, and design notes. Asks guided questions, shows the formatted ticket for confirmation, then creates it via `mcp__sb-jira-flow__create_ticket`.

Tickets live in the Jira project configured in `onboarding.yaml` (`project_management.ticket_prefix`, default `SMASH`). Managed projects in `apexyard.projects.yaml` can override via their own `ticket_prefix`.

## Usage

```
/feature Profile picture upload
/feature Arabic language support
/feature Likes on answers
```

## Process

### 1. Resolve the target Jira project

Determine the Jira project key in this order:

1. If `.claude/session/current-ticket` has `key=<PREFIX>-<N>`, use `<PREFIX>`.
2. Otherwise look up the managed project in `apexyard.projects.yaml` (`ticket_prefix` field) if the current working directory maps to one.
3. Fall back to `project_management.ticket_prefix` in `onboarding.yaml` (default `SMASH`).

If the cwd doesn't map to exactly one managed project AND no active ticket marker exists, ask:

```
Which Jira project is this feature for? (default: SMASH)
```

### 2. Parse or ask for the title

Take the title from `$ARGUMENTS`. If empty, ask:

```
What's the feature? Give me a short title (imperative — "Add …", "Support …", etc.).
```

Run `mcp__sb-jira-flow__validate_ticket_title` to confirm the title meets the convention. If it rejects, suggest the corrected form and re-confirm.

### 3. Gather details (one question at a time)

Ask conversationally — do NOT batch.

**a) User Story**

```
Who is this for and what do they want?
Format: As a [persona], I want [goal] so that [benefit].
```

If the user gives a casual answer, restructure into the user-story format and confirm.

**b) Acceptance Criteria**

```
What are the acceptance criteria? List the specific things that must be true when this is done.
(Bullets are fine — I'll format them.)
```

Require at least one.

**c) Design Notes**

```
Any design notes? (screenshots, mockups, Figma links, or "no UI changes")
```

Default "No UI changes" on "no"/"none".

**d) Priority**

```
Priority?
1. P0 — must-have for current milestone   (→ Jira priority: Highest)
2. P1 — ship soon after launch            (→ Jira priority: High)
3. P2 — future / v2+                      (→ Jira priority: Medium)
```

**e) Component (required for SMASH)**

```
Which component / feature area? (e.g. "TikTok Feed", "Dashboard", "Instagram Feed")
```

**f) Out of Scope (optional)**

```
Anything explicitly out of scope? (or press Enter to skip)
```

### 4. Show the formatted ticket for confirmation

```
Here's the ticket I'll create in {PROJECT_KEY}:

---
Title: {title}
Type: Feature

Description:
As a {persona}, I want {goal} so that {benefit}.

Design Notes:
{notes}

Out of Scope:
{out of scope or "—"}

Acceptance Criteria:
- {criterion 1}
- {criterion 2}

Priority: {Highest|High|Medium}
Component: {component}
Labels: needs-triage, {p0|p1|p2}
---

Create this ticket in Jira? (yes / edit / cancel)
```

### 5. Handle response

- **yes** / **looks good** / **go** → create the ticket
- **edit** / **change X** → ask what to change, update, re-show
- **cancel** / **no** → abort

### 6. Create the Jira ticket

Use the two-phase `mcp__sb-jira-flow__create_ticket` flow:

**Phase 1** — validate + plan:

```
mcp__sb-jira-flow__create_ticket({
  title: "{title}",
  type: "feature",
  description: "{user story + design notes + out of scope}",
  acceptance_criteria: [ "{ac1}", "{ac2}", ... ],
  persona: "{persona}",
  objective: "{goal + benefit}",
  component: "{component}",
  labels: ["needs-triage", "{p0|p1|p2}"]
})
```

**Phase 2** — execute with returned `ticket_id`:

```
mcp__sb-jira-flow__create_ticket({
  ticket_id: "{SMASH-N returned from phase 1}",
  title: "{title}",
  type: "feature",
  description: "...", acceptance_criteria: [...],
  persona: "...", objective: "...",
  component: "...", labels: [...],
  base_branch: "main"
})
```

The MCP also creates a feature branch of the form `feature/SMASH-N-{slug}`.

### 7. Return the URL + next step

```
Created: {JIRA_KEY} — {title}
{JIRA_BASE_URL}/browse/{JIRA_KEY}

Branch created: feature/{JIRA_KEY}-{slug}

Next: /start-ticket {JIRA_KEY} to activate it for this session.
```

## Rules

1. **One question at a time.** Never batch. Wait for each answer.
2. **Always confirm before creating.** Show the full ticket and get explicit "yes".
3. **User story format is required.** Restructure casual answers into As a / I want / So that.
4. **At least one acceptance criterion.** Don't create tickets with empty ACs.
5. **Component is required for SMASH** — the sb-jira-flow MCP will reject without it.
6. **Priority maps to Jira priority** — P0→Highest, P1→High, P2→Medium.
