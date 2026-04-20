---
name: bug
description: Create a structured bug report in Jira with Given/When/Then scenario, repro steps, and severity. Use when reporting a bug or unexpected behavior.
argument-hint: "<short description of the bug>"
allowed-tools: Bash, Read, Write, mcp__sb-jira-flow__create_ticket, mcp__sb-jira-flow__validate_ticket_title, mcp__sb-jira-flow__save_atlassian_config
---

# /bug — Create a Bug Report Ticket (Jira)

Creates a structured Jira ticket for a bug with Given/When/Then scenario, repro steps, environment, and severity. Asks guided questions, shows the formatted ticket, then creates it via `mcp__sb-jira-flow__create_ticket`.

## Usage

```
/bug Profile picture upload fails
/bug RTL resets on navigation
/bug Follow button state not persisted
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
What's the bug? Give me a short description.
```

Run `mcp__sb-jira-flow__validate_ticket_title` to confirm convention. Bug titles should be imperative/declarative describing the broken behaviour (e.g. "Upload fails when file exceeds 5MB").

### 3. Gather details (one question at a time)

**a) Bug Scenario**

```
Describe the bug scenario:
- Given: what's the starting state?
- When: what action triggers the bug?
- Then: what happens (the broken behavior)?
- Expected: what should happen instead?
```

If the user gives a casual description, restructure into Given/When/Then/Expected and confirm.

**b) Repro Steps**

```
What are the exact steps to reproduce?
```

Require at least one.

**c) Severity**

```
How severe is this?
1. P0 — blocks a core feature, must fix immediately   (→ Jira priority: Highest)
2. P1 — important, fix soon                           (→ Jira priority: High)
3. P2 — minor, fix when convenient                    (→ Jira priority: Medium)
```

**d) Component (required for SMASH)**

```
Which component / feature area? (e.g. "TikTok Feed", "Dashboard")
```

**e) Environment (optional)**

```
Any environment details? (browser, device, staging/prod, or Enter to skip)
```

**f) Investigation Notes (optional)**

```
Any initial investigation? (root cause hypothesis, relevant code paths, or Enter to skip)
```

### 4. Show the formatted ticket for confirmation

```
Here's the ticket I'll create in {PROJECT_KEY}:

---
Title: {title}
Type: Bug

Description:
**Given** {precondition}
**When** {action}
**Then** {unexpected result}
**Expected** {correct behavior}

Environment:
{environment or "Not specified"}

Investigation Notes:
{notes or "—"}

Steps to Reproduce:
1. {step 1}
2. {step 2}

Acceptance Criteria (resolution):
- Bug no longer reproduces following the steps above
- Expected behavior from the scenario is observed

Priority: {Highest|High|Medium}
Component: {component}
Labels: bug, {p0|p1|p2}
---

Create this ticket in Jira? (yes / edit / cancel)
```

### 5. Handle response

- **yes** → create the ticket
- **edit** → ask what to change, update, re-show
- **cancel** → abort

### 6. Create the Jira ticket

```
mcp__sb-jira-flow__create_ticket({
  title: "{title}",
  type: "bug",
  description: "{Given/When/Then/Expected + env + investigation}",
  steps_to_reproduce: "1. ...\n2. ...",
  acceptance_criteria: ["Bug no longer reproduces", "Expected behavior observed"],
  component: "{component}",
  labels: ["bug", "{p0|p1|p2}"]
})
```

Then phase 2 with the returned `ticket_id` and `base_branch: "main"`.

### 7. Return the URL + next step

```
Created: {JIRA_KEY} — {title}
{JIRA_BASE_URL}/browse/{JIRA_KEY}

Branch created: fix/{JIRA_KEY}-{slug}

Next: /start-ticket {JIRA_KEY} to activate it for this session.
```

## Rules

1. **One question at a time.** Never batch. Wait for each answer.
2. **Always confirm before creating.** Show the full ticket and get explicit "yes".
3. **Given/When/Then is required.** Restructure casual descriptions into the format.
4. **At least one repro step.** Don't create bugs without repro.
5. **Component is required for SMASH.**
6. **Severity maps to Jira priority** — P0→Highest, P1→High, P2→Medium.
