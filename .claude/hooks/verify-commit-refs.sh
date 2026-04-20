#!/bin/bash
# PreToolUse hook on `git commit -m / -F`: scans the commit message for Jira
# smart-commit references (Closes SMASH-123, Fixes SMASH-45, etc.) and blocks
# the commit if any reference points at an issue that doesn't exist in Jira.
#
# Backstop for the ticket-vocabulary rule (.claude/rules/ticket-vocabulary.md).
# The primary enforcement is self-discipline: never use tracker notation for
# plan items that have no real issue behind them. This hook catches the
# downstream symptom — a fabricated SMASH-N that made it into a commit
# message on its way to becoming durable history.
#
# Jira smart-commit syntax is the bare key (no `#` sigil). We accept any
# 2-10 char uppercase project prefix so a team with multiple Jira projects
# (e.g. SMASH + APEX) works out of the box.
#
# Interactive commits (no -m / -F) are NOT checked. Parsing .git/COMMIT_EDITMSG
# before the editor opens would race with git's own validation. Accepted gap.
#
# If Jira creds aren't available, WARN and pass — /start-ticket + skills
# enforce strong validation via MCP.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib-jira.sh
. "$SCRIPT_DIR/_lib-jira.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only check on git commit
if ! echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
  exit 0
fi

# Extract the commit message. Try -m "..." / -m '...' first, then -F <file>.
# If neither is present, assume interactive commit — skip.
#
# Claude commonly uses multi-line -m args via HEREDOC:
#   git commit -m "$(cat <<EOF ... EOF)"
# The literal -m value spans multiple lines in the command string. `sed -nE`
# processes stdin line-by-line, so a regex like `-m "([^"]*)"` cannot span
# lines. Fix: flatten the command string with `tr '\n' ' '` first.
COMMAND_FLAT=$(echo "$COMMAND" | tr '\n' ' ')

MSG=""

# -m 'single quoted'
MSG=$(echo "$COMMAND_FLAT" | sed -nE "s/.*-m[[:space:]]+'([^']*)'.*/\1/p" | head -1)

# -m "double quoted"
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND_FLAT" | sed -nE 's/.*-m[[:space:]]+"([^"]*)".*/\1/p' | head -1)
fi

# -F <file> / --file <file>
if [ -z "$MSG" ]; then
  MSG_FILE=$(echo "$COMMAND_FLAT" | sed -nE 's/.*(-F|--file)[[:space:]]+([^[:space:]]+).*/\2/p' | head -1)
  if [ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ]; then
    MSG=$(cat "$MSG_FILE")
  fi
fi

# No message found → interactive commit or parse failure. Skip.
if [ -z "$MSG" ]; then
  exit 0
fi

# Extract Jira references. Patterns matched (case-insensitive):
#   Closes SMASH-N / Close SMASH-N / Closed SMASH-N
#   Fixes SMASH-N / Fix SMASH-N / Fixed SMASH-N
#   Resolves SMASH-N / Resolve SMASH-N / Resolved SMASH-N
#   Refs SMASH-N / Ref SMASH-N / References SMASH-N / Related to SMASH-N
#
# Jira-key pattern: 2-10 uppercase chars + dash + digits. No `#` prefix.
REFS=$(echo "$MSG" | grep -oEi '\b(close[sd]?|fix(e[sd])?|resolve[sd]?|ref(s|erences)?|related to)[[:space:]]+[A-Z]{2,10}-[0-9]+' | grep -oE '[A-Z]{2,10}-[0-9]+' | sort -u)

if [ -z "$REFS" ]; then
  exit 0
fi

if ! jira_available; then
  echo "WARN: Jira creds not available (JIRA_EMAIL / JIRA_API_TOKEN). Skipping ticket existence check for: $REFS" >&2
  exit 0
fi

# Verify each referenced issue exists. Fabricated SMASH-N (issue not found)
# is BLOCKING — that's the failure mode the ticket-vocabulary rule targets.
# References to closed issues are WARNED (not blocked) because a commit may
# legitimately reference the closed issue it just finished (revert, follow-up
# clarification after the closing PR shipped). The PR-level hook enforces
# "every PR needs its own OPEN ticket".
MISSING=""
CLOSED=""
for REF in $REFS; do
  if ! jira_issue_exists "$REF"; then
    MISSING="${MISSING}${REF} "
    continue
  fi
  if jira_is_closed "$REF"; then
    CLOSED="${CLOSED}${REF} "
  fi
done

if [ -n "$MISSING" ]; then
  cat >&2 <<MSG
BLOCKED: Commit message references Jira issues that do not exist:
  ${MISSING}

This is the failure mode the ticket-vocabulary rule exists to prevent — do NOT
use Jira notation (Closes SMASH-N, Refs SMASH-N, etc.) for plan items that
have no real issue behind them. See .claude/rules/ticket-vocabulary.md.

If you intended to reference a real issue, verify the key.
If you were about to commit work that has no ticket yet, create one first:
  /bug, /feature, or /task
and use the returned SMASH-N in your commit message.

If the reference is truly informational (e.g. a GitHub PR in another repo
that can't be verified as a Jira key), write it as a plain URL instead.
MSG
  exit 2
fi

if [ -n "$CLOSED" ]; then
  cat >&2 <<MSG
WARN: Commit message references closed Jira issue(s):
  ${CLOSED}
This commit is allowed through — a commit may legitimately reference the
issue it just closed. But at PR-create time the stricter rule applies: every
PR needs its own OPEN ticket. If this commit will end up in a PR that points
at the closed issue as its primary ticket, create a new open ticket first.
MSG
fi

exit 0
