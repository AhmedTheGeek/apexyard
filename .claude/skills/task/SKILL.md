---
name: task
description: Create a structured technical task ticket in Jira with driver, scope, and acceptance criteria. Use for tech debt, infrastructure work, refactoring, or non-user-facing changes.
argument-hint: "<short title of the task>"
allowed-tools: Bash, Read, Write, mcp__sb-jira-flow__create_ticket, mcp__sb-jira-flow__validate_ticket_title, mcp__sb-jira-flow__save_atlassian_config
---

# /task — Create a Technical Task Ticket (Jira)

Creates a structured Jira ticket for a technical task with driver (why), scope (what), acceptance criteria, and risks. Used for tech debt, infrastructure, refactoring, dependency updates, or any non-user-facing work that doesn't fit `/feature` or `/bug`.

## Usage

```
/task Set up PR-triggered CI pipeline
/task Extract shared LikeCount component
/task Migrate from DiceBear to local avatars
```

## Process

### 1. Resolve the target Jira project

Same resolution as `/feature`:

1. `.claude/session/current-ticket` → `key=<PREFIX>-<N>` → use `<PREFIX>`
2. `apexyard.projects.yaml` project `ticket_prefix`
3. `onboarding.yaml` `project_management.ticket_prefix` (default `SMASH`)

Ask only if ambiguous.

### 2. Parse or ask for the title

Take the title from `$ARGUMENTS`. If empty, ask:

```
What's the task? Give me a short title.
```

Run `mcp__sb-jira-flow__validate_ticket_title` for convention.

### 3. Gather details (one question at a time)

**a) Driver**

```
Why is this work needed? (upstream ticket, tech debt rationale, Rex recommendation, dependency requirement, etc.)
```

**b) Scope**

```
What specifically needs to change? Be concrete — which files, services, or systems are affected.
```

**c) Acceptance Criteria**

```
What are the acceptance criteria? What must be true when this is done?
```

Require at least one.

**d) Priority**

```
Priority?
1. P0 — blocks other work                    (→ Jira priority: Highest)
2. P1 — important, schedule soon             (→ Jira priority: High)
3. P2 — nice to have, do when convenient     (→ Jira priority: Medium)
```

**e) Component (required for SMASH)**

```
Which component / feature area?
```

**f) Risks / Dependencies (optional)**

```
Any risks or dependencies? (or Enter to skip)
```

### 4. Show the formatted ticket for confirmation

```
Here's the ticket I'll create in {PROJECT_KEY}:

---
Title: {title}
Type: Task

Description:
**Driver:** {why this work is needed}

**Scope:** {what specifically needs to change}

**Risks / Dependencies:** {risks or "None identified"}

Acceptance Criteria:
- {criterion 1}
- {criterion 2}

Priority: {Highest|High|Medium}
Component: {component}
Labels: {type}, {p0|p1|p2}
---

Create this ticket in Jira? (yes / edit / cancel)
```

The `{type}` label is derived from the content:

- Testing work → `testing`
- CI/CD work → `ci`
- Refactoring → `refactor`
- Everything else → `chore`

### 5. Handle response

- **yes** → create the ticket
- **edit** → update, re-show
- **cancel** → abort

### 6. Create the Jira ticket

```
mcp__sb-jira-flow__create_ticket({
  title: "{title}",
  type: "task",
  description: "**Driver:** ... **Scope:** ... **Risks:** ...",
  acceptance_criteria: ["{ac1}", "{ac2}"],
  component: "{component}",
  labels: ["{chore|refactor|ci|testing}", "{p0|p1|p2}"]
})
```

Then phase 2 with the returned `ticket_id` and `base_branch: "main"`.

### 7. Return the URL + next step

```
Created: {JIRA_KEY} — {title}
{JIRA_BASE_URL}/browse/{JIRA_KEY}

Branch created: {refactor|chore}/{JIRA_KEY}-{slug}

Next: /start-ticket {JIRA_KEY} to activate it for this session.
```

## Rules

1. **One question at a time.** Never batch. Wait for each answer.
2. **Always confirm before creating.** Show the full ticket and get explicit "yes".
3. **Driver is required.** Every technical task needs a "why".
4. **At least one acceptance criterion.** Don't create tasks with empty ACs.
5. **Priority maps to Jira priority** — P0→Highest, P1→High, P2→Medium.
