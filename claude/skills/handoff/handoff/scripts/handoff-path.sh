#!/usr/bin/env bash
# Print the handoff-state.md path for the current project.
# Mirrors Claude Code's project-dir encoding: every non-alphanumeric char -> "-"
set -euo pipefail

cwd="${1:-$PWD}"
# Normalize Git-Bash style /c/Users/... back to C:/Users/...
if [[ "$cwd" =~ ^/([a-zA-Z])/(.*)$ ]]; then
  cwd="$(printf "%s" "${BASH_REMATCH[1]}" | tr "a-z" "A-Z"):/${BASH_REMATCH[2]}"
fi
slug="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
dir="$HOME/.claude/projects/$slug/memory"
mkdir -p "$dir"
printf '%s/handoff-state.md\n' "$dir"
