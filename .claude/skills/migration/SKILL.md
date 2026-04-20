---
name: migration
description: Create a database-migration AgDR (and optionally a paired Jira ticket) in one guided flow. Use BEFORE touching any migration files (migrate-*.ts, migrations/*, Prisma / TypeORM / Alembic dirs, infrastructure DB resources) — the require-migration-ticket.sh hook blocks edits to those paths until a migration AgDR exists at docs/agdr/AgDR-NNNN-*migration*.md.
argument-hint: "[<project>]"
allowed-tools: Bash, Read, Write, mcp__sb-jira-flow__create_ticket, mcp__sb-jira-flow__validate_ticket_title
---

# /migration — Create a Migration AgDR (+ optional Jira ticket)

Migrations are high-blast-radius: data loss, downtime, lock contention, cross-service coordination. ApexYard treats them as a distinct class of change from code — a migration PR needs an **Agent Decision Record** at `docs/agdr/AgDR-NNNN-migration-<slug>.md` that captures the options considered, rollback plan, downtime estimate, cross-service consumers, data volume, testing plan, and observability.

Awesome Motive's Jira workflow doesn't model migrations as a distinct ticket class — migrations ride on regular Story or Task tickets. The AgDR file on disk is what `require-migration-ticket.sh` checks for; the ticket is the tracking record.

## Usage

```
/migration                 # prompts for everything, creates AgDR in the current project; asks whether to create a paired Jira ticket
/migration curios-dog      # explicitly target a registered project
```

## When to invoke

- Before writing a new SQL migration file
- Before adding/modifying a DynamoDB table in infrastructure templates
- Before adding/modifying an `aws_rds_*` / `aws_dynamodb_table` resource in Terraform
- Before editing a Prisma schema in a way that will produce a migration
- Before editing TypeORM / Alembic migration directories
- Generally: BEFORE the first `Write` on anything the migration-gate hook blocks

## Process

### 1. Resolve the target project

If the user passed `<project>`, use that. Otherwise:

- If cwd is under `<ops_root>/workspace/<project>/`, infer project from the path
- Otherwise ask explicitly: "Which project is this migration for?"

Look up the project in `apexyard.projects.yaml` to get `ticket_prefix` (for the optional Jira ticket) and `workspace` (for computing the AgDR path). If the project isn't registered, fall back to the ops repo and use the default `ticket_prefix` from `onboarding.yaml`.

### 2. Gather the migration facts (conversational)

Ask each of the following. Each answer feeds both the AgDR and (optionally) the Jira ticket — the skill writes them into both so the user never retypes.

1. **One-line summary** — e.g. "Add `referrer_source` column to `users` table"
2. **Migration type** — `schema | data | sql | orm` (pick one; if it straddles, use the most invasive)
3. **Affected tables / entities** — comma-separated list. Required non-empty.
4. **Rollback plan** — free text, required non-empty. Ask: "if this goes wrong in prod at 3am, what exactly does the rollback runbook look like?" Capture the actual steps, not a promise to figure it out later.
5. **Rollback tested against** — `staging | copy of prod | unit fixture | not tested`. If "not tested", flag it in the AgDR and tell the user this is a blocker for prod apply (not for creating the AgDR).
6. **Estimated downtime** — `none | seconds | minutes | hours`. Plus reasoning: "why this much / this little?"
7. **Cross-service consumers** — list every service that reads or writes the affected tables. If genuinely none, say so.
8. **Deploy-order constraint** — if any service must deploy before or after this migration, record it.
9. **Data volume** — rough row/item count. If unknown, note that and add "size check" to the testing plan.
10. **Testing plan** — dev smoke command, staging verify steps, canary / phased rollout if applicable.
11. **Observability** — metrics/logs that will confirm success during and after. Link dashboards if they exist.
12. **Priority** — `P0 | P1 | P2 | P3`. Default `P1` for migrations.
13. **Component (for SMASH ticket)** — required if the user opts to create a paired Jira ticket in step 6.

Re-prompt if rollback plan is empty, affected tables is empty, or priority is missing — these are the three fields with no safe default.

### 3. Preview

Before creating anything, echo back a structured preview:

```
AgDR:
  Path:         <repo-root>/docs/agdr/AgDR-NNNN-migration-<slug>.md
  Next number:  NNNN = max(existing AgDR ids in that dir) + 1

Jira ticket (optional — asked in step 6):
  Project:      {PROJECT_KEY} (from {onboarding.yaml | registry})
  Title:        [Migration] <type>: <summary>
  Type:         Task
  Labels:       migration, {p0|p1|p2|p3}
  Component:    <component>
```

### 4. Write the AgDR first

Copy `templates/agdr-migration.md` to the resolved path (creating `docs/agdr/` if needed), filling in:

- Frontmatter (`id`, `timestamp`, `agent`, `model`, `trigger: user-prompt`, `status: draft`, `ticket: TBD`)
- Title, one-sentence summary, and every Section (Context, Options, Decision, Rollback Plan, Cross-Service Consumers, Testing Plan, Observability, Consequences) with the user's answers

AgDRs are written in the RIGHT repo:

| Where the migration runs | AgDR path |
|--------------------------|-----------|
| Inside a managed project's own code repo | `workspace/<project>/docs/agdr/AgDR-NNNN-migration-<slug>.md` |
| Against the apexyard framework itself | `docs/agdr/AgDR-NNNN-migration-<slug>.md` in the ops fork |

For the `NNNN` id: scan the target `docs/agdr/` directory for existing `AgDR-\d+-.*\.md` files, take the max id, increment. Zero-pad to 4 digits.

The filename must include `migration` so `require-migration-ticket.sh`'s `AgDR-*migration*.md` glob matches.

### 5. Ask whether to create a paired Jira ticket

```
Create a paired Jira ticket in {PROJECT_KEY} to track the work? (y/n, default y)
```

The migration gate doesn't require a ticket — it only checks for the AgDR. But a ticket is the right place for team-visible status ("not started" / "in progress" / "shipped to staging"), and it's where stakeholder-update will pick it up. The default is yes.

### 6. (If y) Create the Jira ticket via MCP

```
mcp__sb-jira-flow__create_ticket({
  title: "[Migration] <type>: <summary>",
  type: "task",
  description: <<EOF
## Migration

**Type**: <type>
**Affected tables/entities**: <list>
**Estimated downtime**: <level> — <reasoning>
**Data volume**: <count or "unknown">
**Priority**: <priority>

## Rollback Plan

<rollback plan verbatim>

**Tested against**: <staging | copy of prod | unit fixture | not tested>

## Cross-Service Consumers

<list or "none">

**Deploy-order constraint**: <constraint or "none">

## Testing Plan

- Dev smoke: <command>
- Staging verify: <steps>
- Canary / phased rollout: <plan or "n/a">

## Observability

<what to watch during + after>

## Agent Decision Record

Migration AgDR: `<relative-path-to-AgDR>`
EOF,
  acceptance_criteria: [
    "Migration applies cleanly in dev + staging",
    "Rollback steps from AgDR executed once in staging",
    "Post-apply observability checks pass"
  ],
  component: "<component>",
  labels: ["migration", "<p0|p1|p2|p3>"]
})
```

Then phase 2 with the returned `ticket_id` + `base_branch: "main"`.

### 7. Back-fill the AgDR with the ticket reference (if created)

Open the AgDR written in step 4 and update:

- Frontmatter `ticket: <JIRA_KEY>`
- The Artifacts section: add `{JIRA_BASE_URL}/browse/<JIRA_KEY>`

This lets a future reader land on the AgDR and find the ticket, and land on the ticket and find the AgDR.

### 8. Return a summary

```
Migration AgDR:   <relative-path-to-AgDR>
Migration ticket: <JIRA_KEY> — {JIRA_BASE_URL}/browse/<JIRA_KEY>   (or "skipped")
Next step:        /start-ticket <JIRA_KEY>, then begin editing the migration files
```

**Do NOT automatically run `/start-ticket`** — the user may have other context to set first, and the explicit handoff makes the workflow legible. The migration gate will block edits until the AgDR exists on disk (it now does, so you're unblocked).

## Rules

1. **Never ship without a rollback plan**. If the user cannot articulate rollback steps, the migration isn't ready — the skill refuses to create the AgDR until they type something in that field.
2. **Never auto-assign priority**. Migrations span from "trivial schema rename" (P3) to "primary-key column type change on a 100M-row table at peak traffic" (P0). Ask.
3. **Never skip the AgDR**. Even small migrations get one. If it feels like overkill for a 3-line change, the AgDR entries will be short — that's fine. The value is in the forcing function of thinking through rollback + observability.
4. **Never create the AgDR under `.claude/` or `docs/` unless the migration IS against apexyard itself**. For managed projects, the AgDR lives inside that project's repo (`workspace/<project>/docs/agdr/`), not in the ops fork.
5. **Write AgDR first, ticket second, back-fill third** — the AgDR is a local file, reversible with `rm`. The ticket is remote state.
6. **The ticket is optional, the AgDR is not** — `require-migration-ticket.sh` only gates on the AgDR. The ticket is for team visibility; default-yes but allow skipping.

## Relation to the migration gate

| Hook | `require-migration-ticket.sh` (fires PreToolUse on Write/Edit to migration paths) |
|------|------------------------------------------------------------------------------------|
| Gate 1 | Active ticket exists (handled by require-active-ticket.sh) |
| Gate 2 | A migration AgDR exists at `docs/agdr/AgDR-\d+-.*migration.*\.md` |
| Fail message | Points at this skill |

The skill and the gate are two halves of the same mechanism: gate detects the situation and blocks, skill builds the AgDR that unblocks.
