#!/bin/bash
# Validates PR creation:
# - PR title matches format: type(JIRA-KEY): description
# - PR body contains a Glossary section
# - Branch has a Jira key
# - The Jira key in the title actually exists and isn't Done/Cancelled
#   (backstop for the ticket-vocabulary rule — catches fabricated SMASH-N
#   that slipped through prose into a PR title)
#
# Tickets live in Jira. PRs + CI live on GitHub. The PR title carries a Jira
# key in its scope (e.g. `feat(SMASH-123): add auth`). The issue-existence
# check is delegated to _lib-jira.sh, which hits api/3/issue/<KEY>. If Jira
# creds aren't available, the hook WARNs and passes (skills enforce at
# ticket-start time via MCP).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib-jira.sh
. "$SCRIPT_DIR/_lib-jira.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only check on gh pr create
if ! echo "$COMMAND" | grep -qE '\bgh\s+pr\s+create\b'; then
  exit 0
fi

ERRORS=""

# Extract --title value (macOS-compatible, no grep -P)
TITLE=$(echo "$COMMAND" | sed -n 's/.*--title[[:space:]]*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/p' | head -1)
if [ -z "$TITLE" ]; then
  TITLE=$(echo "$COMMAND" | sed -n 's/.*--title[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
fi

# Validate PR title format. Accepts: type(<JIRA-KEY>): … or type(<JIRA-KEY>)!: …
# <JIRA-KEY> = 2-10 char uppercase prefix + dash + digits.
# The !? makes the breaking-change marker optional per Conventional Commits 1.0.
# Aligned with pr-title-check.yml so passing here = passing CI.
JIRA_KEY=""
if [ -n "$TITLE" ]; then
  if ! echo "$TITLE" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\([A-Z]{2,10}-[0-9]+\)!?:'; then
    ERRORS="${ERRORS}PR title '$TITLE' doesn't match format: type(JIRA-KEY): description (e.g. feat(SMASH-123): add auth)\n"
  else
    JIRA_KEY=$(echo "$TITLE" | sed -nE 's/^[a-z]+\(([A-Z]{2,10}-[0-9]+)\).*/\1/p')
  fi
fi

# Verify the Jira key actually exists and isn't closed.
# Backstop for ticket-vocabulary.md — catches fabricated SMASH-N in PR titles.
if [ -n "$JIRA_KEY" ]; then
  if jira_available; then
    if ! jira_issue_exists "$JIRA_KEY"; then
      cat >&2 <<MSG
BLOCKED: PR title references ${JIRA_KEY} but that issue does not exist
in Jira ($(jira_issue_url "$JIRA_KEY")).

This is the failure mode the ticket-vocabulary rule exists to prevent — do NOT
use Jira notation for plan items that have no real issue behind them.
See .claude/rules/ticket-vocabulary.md § "The rule".

If you intended to create the PR for a real ticket, verify the key.
If you were about to file work that has no ticket yet, create one first:
  /bug, /feature, or /task
and use the returned SMASH-N in your PR title.
MSG
      exit 2
    fi

    if jira_is_closed "$JIRA_KEY"; then
      STATE=$(jira_issue_state "$JIRA_KEY")
      cat >&2 <<MSG
BLOCKED: PR title references ${JIRA_KEY} but that issue is ${STATE} in Jira
($(jira_issue_url "$JIRA_KEY")).

Every PR needs its own OPEN ticket. Referencing a done/cancelled issue means
the PR has no live acceptance criteria, no QA handoff, and no tracker row to
move through the SDLC states — the ticket is already finished.

Common causes:
  - The work is a follow-up to a closed issue → create a NEW ticket via
    /bug, /feature, or /task, link back to ${JIRA_KEY} in the description,
    and use the new key in the PR title.
  - The closed issue was resolved by a prior PR that didn't fully finish the
    work → re-open it in Jira or create a new ticket for the remaining work.
  - The key is a typo → fix the PR title.

See .claude/rules/ticket-vocabulary.md and the "every PR needs its own open
ticket" rule in .claude/rules/pr-quality.md.
MSG
      exit 2
    fi
  else
    echo "WARN: Jira creds not available (JIRA_EMAIL / JIRA_API_TOKEN). Skipping ticket existence check for ${JIRA_KEY}." >&2
  fi
fi

# Check PR body for Glossary section
if echo "$COMMAND" | grep -q '\-\-body'; then
  if ! echo "$COMMAND" | grep -qiE '##\s*(Glossary|glossary)'; then
    ERRORS="${ERRORS}PR body missing required '## Glossary' section.\n"
  fi
fi

# Validate branch name has a Jira key
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  if ! echo "$CURRENT_BRANCH" | grep -qE '[A-Z]{2,10}-[0-9]+'; then
    ERRORS="${ERRORS}Branch '$CURRENT_BRANCH' missing Jira key (expected something like feature/SMASH-123-slug).\n"
  fi
fi

if [ -n "$ERRORS" ]; then
  echo "PR VALIDATION BLOCKED:" >&2
  printf "$ERRORS" >&2
  echo "" >&2
  echo "Fix the issues above before creating the PR." >&2
  echo "See .claude/rules/git-conventions.md and .claude/rules/pr-quality.md." >&2
  exit 2
fi

exit 0
