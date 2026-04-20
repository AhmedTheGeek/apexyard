#!/bin/bash
# PreToolUse hook on Write/Edit/MultiEdit: when the target path looks like a
# database migration file, enforce that a migration AgDR exists. The active-
# ticket gate (require-active-ticket.sh) runs alongside this and handles the
# "ticket must exist" check — this hook exclusively guards the code-hygiene
# side: a migration-class change needs an Agent Decision Record describing
# rollback plan, downtime, cross-service consumers, and observability.
#
# This hook does NOT check the Jira ticket for a `migration` label or type.
# Awesome Motive's Jira workflow doesn't model migrations as a distinct
# ticket class — migrations are regular Story / Task tickets. The AgDR
# file on disk is the durable record.
#
# Gates in order:
#
#   G1. (handled by require-active-ticket.sh — we rely on that hook's check)
#   G2. A migration AgDR exists at
#       docs/agdr/AgDR-\d+-.*migration.*\.md within the ops root or the
#       repo root.
#
# Pass-through (exit 0) paths:
#   - FILE_PATH doesn't match any migration-path pattern
#   - FILE_PATH is under .claude/, docs/, projects/*/docs/, any *.md
#   - Any *.example file (migration templates in golden-paths/ etc.)
#
# Path patterns are overridable per project via
# `.claude/project-config.json`:
#
#   { "migration_paths": ["src/db/**", "db/migrations/**"] }

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --------- Exempt meta / docs / example files ---------
case "$FILE_PATH" in
  */.claude/*|*/.claude|*/docs/*|*/docs) exit 0 ;;
  *.md|*.example) exit 0 ;;
esac

# --------- Discover ops root ---------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
OPS_ROOT=""
if [ -n "$REPO_ROOT" ]; then
  r="$REPO_ROOT"
  while [ -n "$r" ] && [ "$r" != "/" ]; do
    if [ -f "$r/onboarding.yaml" ] && [ -f "$r/apexyard.projects.yaml" ]; then
      OPS_ROOT="$r"
      break
    fi
    r=$(dirname "$r")
  done
fi

# --------- Load project-config overrides ---------
CUSTOM_PATHS=""
CONFIG_HOME="${OPS_ROOT:-$REPO_ROOT}"
PCONFIG="$CONFIG_HOME/.claude/project-config.json"
if [ -f "$PCONFIG" ] && command -v jq >/dev/null 2>&1; then
  CUSTOM_PATHS=$(jq -r '.migration_paths // [] | join("\n")' "$PCONFIG" 2>/dev/null)
fi

# --------- Does this path look like a migration? ---------
is_migration_path() {
  local path="$1"

  if [ -n "$CUSTOM_PATHS" ]; then
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      # shellcheck disable=SC2254
      case "$path" in
        $pat) return 0 ;;
      esac
    done <<< "$CUSTOM_PATHS"
    return 1
  fi

  case "$path" in
    */migrations/*.sql) return 0 ;;
    */migrate-*.ts|*/migrate-*.js|*/migrate-*.py|*/migrate-*.sql) return 0 ;;
    */prisma/schema.prisma|*/prisma/migrations/*) return 0 ;;
    */src/migrations/*.ts|*/src/migrations/*.js) return 0 ;;
    */alembic/versions/*.py) return 0 ;;
    */db/migrate/*.rb) return 0 ;;
    */migrations/*) return 0 ;;
  esac
  return 1
}

if ! is_migration_path "$FILE_PATH"; then
  exit 0
fi

# --------- Gate 2: migration AgDR exists on disk ---------
# Look under ops root first (framework-level migrations), then the repo root.
# The glob pattern matches the same shape the /migration skill writes:
#   docs/agdr/AgDR-<NNN>-<slug>-migration.md
# but tolerates any filename that contains "migration" after the number.
AGDR_FOUND=""
for root in "$OPS_ROOT" "$REPO_ROOT"; do
  [ -z "$root" ] && continue
  if [ -d "$root/docs/agdr" ]; then
    match=$(find "$root/docs/agdr" -maxdepth 1 -type f -name 'AgDR-*migration*.md' 2>/dev/null | head -1)
    if [ -n "$match" ]; then
      AGDR_FOUND="$match"
      break
    fi
  fi
done

if [ -z "$AGDR_FOUND" ]; then
  cat >&2 <<MSG
BLOCKED: This file looks like a database migration but no migration AgDR
was found.

Path matched: $FILE_PATH
Expected AgDR at: docs/agdr/AgDR-<NNN>-<slug>-migration.md

A migration-class change needs a paired Agent Decision Record capturing
rollback plan, downtime, cross-service consumers, and observability. Create
it now with the /migration skill:

  /migration

The skill walks through the required fields and writes the AgDR file. It
also creates (or reuses) a Jira ticket for the work — but the ticket isn't
what this hook gates on; the AgDR is.

Once the AgDR file exists under docs/agdr/ with "migration" in its name,
retry the edit.
MSG
  exit 2
fi

# All gates passed — allow the edit.
exit 0
