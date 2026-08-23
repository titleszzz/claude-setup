#!/usr/bin/env bash
# SessionStart hook: if this project has a handoff note, print it so the new
# session (or the one resuming after compaction) starts with it in context.
# Plain stdout from SessionStart is added as context Claude can see.
set -uo pipefail

file="$(bash "$HOME/.claude/skills/handoff/scripts/handoff-path.sh" 2>/dev/null)" || exit 0
[ -f "$file" ] || exit 0

age_days=$(( ( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null || echo 0) ) / 86400 ))

echo "=== Handoff note for this project (written ${age_days}d ago) ==="
cat "$file"
echo "=== end handoff note ==="

# Validate it before trusting it: structure, age, and whether the branch and
# dirty files it claims still match live git. Only problems are printed.
# The checker uses node's own cwd, so it derives the same project dir.
check="$(node "$HOME/.claude/skills/handoff/scripts/check-handoff.mjs" 2>/dev/null)"
if [ -n "$check" ]; then
  echo "--- automatic check of the note above ---"
  echo "$check"
fi

echo "Treat the above as a starting point, not the truth. Anything flagged WARN is out of date — verify it against git before acting on it."
