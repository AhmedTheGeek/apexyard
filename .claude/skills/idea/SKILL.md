---
name: idea
description: Submit a new product idea, feature concept, or internal tool proposal to the ideas backlog. Use when capturing a new product concept that hasn't been triaged yet.
argument-hint: "<short title of the idea>"
allowed-tools: Bash, Read, Edit, Write, mcp__sb-jira-flow__create_ticket, mcp__sb-jira-flow__validate_ticket_title
---

# /idea — Submit a New Product Idea

Capture a new product, feature, or internal-tool idea so it lands somewhere durable instead of evaporating in chat. This skill is intentionally lightweight: it adds an entry to the ideas backlog and (optionally) creates a tracking Jira ticket with the `needs-triage` label. It does **not** replace `/write-spec` — that comes later, after the idea has been triaged.

## Usage

```
/idea Auto-tag inbound emails by intent
/idea Internal CLI for resetting staging data
/idea New product: AI design system linter
```

## Where the entry goes

Every idea lands in `projects/ideas-backlog.md` at the root of your ops repo (your fork of apexyard). One shared backlog for every project — triage decides which project ends up owning a given idea.

If the file doesn't exist yet, create it with a header and a table.

## Process

### 1. Parse the title

Take the title from `$ARGUMENTS`. If empty, ask:

```
What's the idea? Give me a short title (1 line).
```

### 2. Gather metadata

Ask conversationally (one question at a time, don't batch):

**Category** — must be one of four values. Present numbered options and **re-prompt on invalid input**:

```
Category?
  1. New Product
  2. Feature
  3. Internal Tool
  4. Process
>
```

Accept `1`, `2`, `3`, `4` or the corresponding word (case-insensitive). On anything else, say `Please pick 1-4 or type the category name.` and re-ask. Loop until valid — do **not** silently accept garbage.

**Submitter** — who's proposing it. Default to the current git user (`git config user.name`). If the user wants to override, accept their input as-is.

**One-line description** — what would it do? Who's it for? If empty, re-prompt: `Give me one sentence about what this idea does.` Loop until non-empty.

Don't go deeper than that — this is a lightweight capture, not a spec.

### 3. Check for duplicates

Before computing an ID or appending anything, fuzzy-match the title against existing backlog entries:

```bash
# Normalise a title: lowercase, strip punctuation, collapse whitespace
normalise() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | tr -s ' '; }

# Extract existing titles from the backlog table
grep -E '^\| IDEA-[0-9]+ \|' projects/ideas-backlog.md 2>/dev/null \
  | awk -F'|' '{print $3}' \
  | sed 's/^ *//;s/ *$//'
```

Compare the normalised new title against every normalised existing title using a simple token-overlap heuristic: if ≥ 80% of the words in the shorter title appear in the longer one, flag as a potential duplicate.

If a potential match is found:

```
⚠ Similar idea already in the backlog:
  IDEA-025 — {existing title} (status: {status})

Is this a duplicate? (y = skip, n = add anyway)
>
```

- `y` → skip the append, return without logging anything new, suggest `/write-spec IDEA-025` if the user wants to work on the existing idea
- `n` → continue to step 4

If no match is found, continue silently to step 4.

### 4. Compute the next ID

```bash
# Find the highest existing IDEA-NNN in the backlog file
grep -oE 'IDEA-[0-9]+' <backlog-file> 2>/dev/null | sort -V | tail -1
# Increment by 1, or start at IDEA-001 if none exist
```

### 5. Append the entry

If the backlog file doesn't exist, create it with this header:

```markdown
# Ideas Backlog

Lightweight capture of product ideas, feature concepts, and internal tool proposals.
Use `/idea` to add a new entry. Triage moves entries into `/write-spec`, then into a Jira ticket.

| ID | Title | Category | Submitter | Date | Status | Description |
|----|-------|----------|-----------|------|--------|-------------|
```

Append a new row:

```markdown
| IDEA-NNN | {title} | {category} | {submitter} | YYYY-MM-DD | NEW | {one-line description} |
```

### 6. Offer the tracking ticket

After the entry is appended, ask:

```
Would you like me to create a tracking Jira ticket for IDEA-NNN? (y/n)
```

If the user says no, skip this step entirely — the backlog entry is already saved, and that's enough.

If yes, create one in the configured Jira project (default `SMASH` from `onboarding.yaml`) with the `needs-triage` label via `mcp__sb-jira-flow__create_ticket`:

```
mcp__sb-jira-flow__create_ticket({
  title: "{title}",
  type: "feature",
  description: "## Idea\n{one-line description}\n\n## Category\n{category}\n\n## Submitter\n{submitter}\n\n## Backlog Entry\nIDEA-NNN — see projects/ideas-backlog.md\n\n## Next Step\nTriage. Decide whether to spec, schedule, or close.",
  acceptance_criteria: ["Idea reviewed at next triage", "Decision recorded (spec / schedule / close)"],
  component: "{component or 'Triage'}",
  labels: ["needs-triage", "idea"]
})
```

Ask for component if not obvious — for an idea this can be `Triage` as a catch-all.

**Error handling** — if the MCP call fails (auth, network, component rejected), fall back gracefully:

```
⚠ Couldn't create the tracking ticket: {reason}
  The idea is still saved in projects/ideas-backlog.md as IDEA-NNN.

  Try again? (y = retry, n = skip)
>
```

The guiding principle: **the backlog entry is the primary artefact; the tracking ticket is a bonus**. Never lose the backlog entry because Jira was flaky.

If the ticket is created successfully, append the Jira key to the backlog row's Description column as `(SMASH-NN)`.

## Output

```
Captured: IDEA-NNN — {title}
Backlog: {file path}
Status: NEW
Tracking ticket: {jira_key + url, or "skipped"}

Next: triage with the team, then `/write-spec` if it survives.
```

## Rules

1. **Lightweight only** — `/idea` captures, it does not spec. Don't ask for goals, metrics, or requirements here.
2. **Always assign an ID** — `IDEA-NNN`, zero-padded to 3 digits.
3. **One row per idea** — never edit existing rows from this skill; new ideas always append.
4. **Status starts at NEW** — triage changes it later.
5. **Single backlog** — every idea goes into `projects/ideas-backlog.md` at the root of the ops repo; triage assigns it to a project later.
6. **Validate before accepting** — category must be 1-4; description must be non-empty. Loop until valid; never silently accept garbage.
7. **Dedup before appending** — fuzzy-match the title against existing entries; flag and confirm before creating a second entry for the same idea.
8. **The backlog is the primary artefact** — if the tracking ticket fails to create, the backlog entry still stands. Never lose data because Jira was flaky.
9. **Don't create the ticket silently** — always ask first.
10. **Never delete** — superseded ideas get status `SUPERSEDED`, not removal.

## Status values

| Status | Meaning |
|--------|---------|
| NEW | Just captured, not triaged |
| TRIAGED | Reviewed, awaiting decision |
| SPECCED | `/write-spec` produced a PRD |
| SHIPPED | Built and released |
| WONTDO | Triaged out — not pursuing |
| SUPERSEDED | Replaced by a different idea |
