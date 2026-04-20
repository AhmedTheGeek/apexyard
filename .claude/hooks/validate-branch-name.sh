#!/bin/bash
# Validates branch naming convention before push.
# Format: {type}/{TICKET-ID}-{description}
#
# TICKET-ID is a Jira key: 2-10 char uppercase project prefix + dash + digits
# (e.g. SMASH-123, APEX-42). The default Jira project lives in
# onboarding.yaml (project_management.ticket_prefix); per-repo overrides
# live in apexyard.projects.yaml.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only check on git push
if ! echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
  exit 0
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

# Allow trunk and shared integration branches
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "develop" ]; then
  exit 0
fi

# Validate: type/<JIRA-KEY>-<description>
#   <JIRA-KEY> = 2-10 char uppercase prefix + dash + digits (e.g. SMASH-123)
# Note: this pattern is intentionally aligned with the pr-title-check.yml
# CI workflow regex so anything that passes this hook also passes CI.
if ! echo "$CURRENT_BRANCH" | grep -qE '^(feature|fix|refactor|chore|docs|test|spike|ci|build|perf)/[A-Z]{2,10}-[0-9]+-'; then
  echo "BLOCKED: Branch '$CURRENT_BRANCH' doesn't follow naming convention: {type}/{JIRA-KEY}-{description}" >&2
  echo "Examples: feature/SMASH-123-add-auth, fix/SMASH-45-login-bug, docs/SMASH-99-update-readme" >&2
  echo "Rename with: git branch -m \"\$(git branch --show-current)\" \"feature/SMASH-XX-description\"" >&2
  echo "Start a ticket with: /start-ticket SMASH-XX" >&2
  exit 2
fi

exit 0
