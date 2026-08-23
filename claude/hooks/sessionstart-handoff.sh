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
echo "Treat the above as a starting point, not the truth. Verify branch and uncommitted files against git before acting on it."
