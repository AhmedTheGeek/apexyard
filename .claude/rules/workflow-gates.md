# Workflow Gates

| Gate | Before | Verify |
|------|--------|--------|
| 1 | PRD → Tech Design | PRD approved, parent epic exists |
| 2 | Tech Design → Build | Design approved, story tickets exist, **AgDR for key decisions** |
| 3 | Starting code | Ticket exists, branch created, design review if UI work |
| 3a | Starting a **migration** edit | A migration AgDR exists at `docs/agdr/AgDR-\d+-.*migration.*\.md` under the ops root or repo root. Enforced by `require-migration-ticket.sh`. Use `/migration` to produce the AgDR (and optionally a paired Jira ticket) in one flow. Jira at Awesome Motive doesn't model migrations as a distinct issue type or label — the AgDR file is the load-bearing artefact. |
| 4 | Creating PR | Tests pass, checks pass, **> 80% coverage**, **AgDR linked if decisions made** |
| 5 | Merging PR | 2 reviews (agent + human), CI green, **commit SHA matches review** |
| 6 | Ticket → Done | QA verified, signed off |

**If a gate fails → STOP. Complete the missing step first.**

## One Ticket at a Time

Work on **one** ticket at a time. Complete it fully before starting the next. Each PR = one ticket only.

```
WRONG:
  Start ticket A → Start ticket B → Start ticket C → PR with all 3

RIGHT:
  Start A → PR → Review → QA → Done
  Start B → PR → Review → QA → Done
  Start C → PR → Review → QA → Done
```

## Pre-Build Gate

Do not start coding until **all** of these exist in your ticket tracker:

- Parent epic / feature ticket (with link to the PRD)
- User story tickets (sub-issues)
- Each story has acceptance criteria
- Technical tasks broken down
- Tickets moved to "Todo" or "In Progress"

## Migration Gate (3a) — AgDR required

Any edit to a file that matches the migration-path patterns (configurable via `.claude/project-config.json` → `migration_paths`) requires a migration AgDR on disk at `docs/agdr/AgDR-\d+-.*migration.*\.md`.

Default migration paths:

- `**/migrate-*.{ts,js,py,sql}` — one-off migration scripts
- `**/migrations/**` — any file under a migrations/ directory
- `prisma/schema.prisma`, `prisma/migrations/**` — Prisma
- `src/migrations/*.{ts,js}` — TypeORM
- `alembic/versions/*.py` — Alembic
- `db/migrate/*.rb` — Rails

**Enforcement**: `require-migration-ticket.sh` fires on PreToolUse for Edit / Write / MultiEdit. If the path matches a migration pattern, it checks for the AgDR. It does NOT check Jira for a `migration` label or issue type — Awesome Motive's Jira workflow doesn't model migrations as a distinct class, so the AgDR is the only durable signal that the author thought through rollback, downtime, consumers, and observability.

`require-active-ticket.sh` runs alongside and still enforces the "active ticket exists" rule.

**How to satisfy**: run `/migration` — it asks for migration type, affected tables, rollback plan, downtime estimate, cross-service consumers, data volume, testing plan, and observability, then writes the AgDR (and optionally creates a paired Jira ticket for status tracking).

## QA State is Mandatory

A merged PR moves the ticket to **QA** state, **not** Done. A QA Engineer manually verifies the acceptance criteria, then moves the ticket to Done.

```
In Progress → In Review → QA → Done
                          ^
                    MANDATORY STOP
                    QA must verify
```
