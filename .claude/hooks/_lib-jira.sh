#!/bin/bash
# Shared Jira helper for hooks that need to verify an issue exists or is open.
# Source — do not execute.
#
#   . "$SCRIPT_DIR/_lib-jira.sh"
#   if jira_available; then
#     if ! jira_issue_exists "$KEY"; then ... ; fi
#   fi
#
# Auth is Basic (email + API token) per
#   https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/#authentication
#
# Env:
#   JIRA_BASE_URL   Workspace URL. Default: https://awesomemotive.atlassian.net
#   JIRA_EMAIL      Account email. No default — must be set for API calls.
#   JIRA_API_TOKEN  Token from id.atlassian.com/manage-profile/security/api-tokens
#
# Caching:
#   5-minute per-issue JSON cache under /tmp/claude-jira-cache-<uid>/ to avoid
#   hammering the API during a burst of edits or commits. Cache is best-effort;
#   failures are silent.
#
# Degradation:
#   jira_available returns 1 when env or curl are missing. Hooks should WARN
#   and pass (not block) when the helper isn't available — skills enforce the
#   strong checks via MCP at ticket-start / ticket-create time.

_JIRA_BASE="${JIRA_BASE_URL:-https://awesomemotive.atlassian.net}"
_JIRA_EMAIL="${JIRA_EMAIL:-}"
_JIRA_TOKEN="${JIRA_API_TOKEN:-}"
_JIRA_CACHE_DIR="/tmp/claude-jira-cache-$(id -u 2>/dev/null || echo 0)"
_JIRA_CACHE_TTL=300  # 5 minutes

jira_available() {
  [ -n "$_JIRA_EMAIL" ] && [ -n "$_JIRA_TOKEN" ] && command -v curl >/dev/null 2>&1
}

# Portable mtime — macOS stat -f vs GNU stat -c.
_jira_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# jira_get_issue KEY — prints JSON to stdout, returns 0 on success.
# Requests a narrow fields set to keep responses small.
jira_get_issue() {
  local key="$1"
  [ -z "$key" ] && return 1
  jira_available || return 1

  mkdir -p "$_JIRA_CACHE_DIR" 2>/dev/null
  local cache="$_JIRA_CACHE_DIR/$key.json"

  if [ -f "$cache" ]; then
    local mtime age
    mtime=$(_jira_mtime "$cache")
    age=$(( $(date +%s) - ${mtime:-0} ))
    if [ "$age" -lt "$_JIRA_CACHE_TTL" ]; then
      cat "$cache"
      return 0
    fi
  fi

  local url="${_JIRA_BASE}/rest/api/3/issue/${key}?fields=summary,status,issuetype,labels"
  local out
  if ! out=$(curl -sf \
      -u "${_JIRA_EMAIL}:${_JIRA_TOKEN}" \
      -H "Accept: application/json" \
      --max-time 8 \
      "$url" 2>/dev/null); then
    return 1
  fi

  echo "$out" > "$cache" 2>/dev/null
  echo "$out"
}

jira_issue_exists() {
  jira_get_issue "$1" >/dev/null 2>&1
}

# Prints Jira status name (e.g. "In Progress", "Done") or empty string.
jira_issue_state() {
  local json
  json=$(jira_get_issue "$1") || return 1
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.fields.status.name // empty'
  else
    echo "$json" | sed -n 's/.*"status":{[^}]*"name":"\([^"]*\)".*/\1/p' | head -1
  fi
}

# Returns 0 iff the issue is in a closed-ish status.
# Default closed-set: Done, Cancelled, Won't Do, Resolved, Closed.
jira_is_closed() {
  local state
  state=$(jira_issue_state "$1") || return 1
  case "$state" in
    Done|Cancelled|"Won't Do"|"Won't Fix"|Resolved|Closed) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints issue type name (Story, Bug, Task, Epic, ...).
jira_issue_type() {
  local json
  json=$(jira_get_issue "$1") || return 1
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.fields.issuetype.name // empty'
  else
    echo "$json" | sed -n 's/.*"issuetype":{[^}]*"name":"\([^"]*\)".*/\1/p' | head -1
  fi
}

# Prints the web URL for an issue key (no API call).
jira_issue_url() {
  echo "${_JIRA_BASE}/browse/$1"
}
