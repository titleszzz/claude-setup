#!/bin/bash
# Capture the live Claude Code + VS Code config on this PC into the repo,
# then commit and push if anything changed.
#
# Run manually:  bash scripts/sync.sh
# Run by hook:   see .claude settings.json (SessionStart / SessionEnd)
#
# Safe to run any time: it is a no-op when nothing changed.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
AGENTS_DIR="$HOME/.agents"
VSC_USER="$HOME/AppData/Roaming/Code/User"
VSC_CLI="$HOME/AppData/Local/Programs/Microsoft VS Code/bin/code"

copy() { [ -e "$1" ] && install -D -m "${3:-644}" "$1" "$2"; }

# --- Claude Code -----------------------------------------------------------
copy "$CLAUDE_DIR/CLAUDE.md"                        "$REPO/claude/CLAUDE.md"
copy "$CLAUDE_DIR/settings.json"                    "$REPO/claude/settings.json"

# settings.json carries an `autoMode.environment` block describing private
# projects and repo paths. Strip it from the mirrored copy — the live file keeps
# it. Fail closed: if the JSON cannot be rewritten, the file is not mirrored.
if [ -f "$REPO/claude/settings.json" ]; then
  python -c '
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    d = json.load(f)
d.pop("autoMode", None)
with open(p, "w", encoding="utf-8", newline="\n") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
' "$REPO/claude/settings.json" || rm -f "$REPO/claude/settings.json"
fi
copy "$CLAUDE_DIR/skills-lock.json"                 "$REPO/claude/skills-lock.json"
copy "$CLAUDE_DIR/statusline-command.sh"            "$REPO/claude/statusline-command.sh" 755
copy "$CLAUDE_DIR/keybindings.json"                 "$REPO/claude/keybindings.json"
copy "$CLAUDE_DIR/plugins/installed_plugins.json"   "$REPO/claude/plugins/installed_plugins.json"
copy "$CLAUDE_DIR/plugins/known_marketplaces.json"  "$REPO/claude/plugins/known_marketplaces.json"

# Skills: mirror real directories only. Symlinked skills are recorded, not copied.
# A skill holding a `.local-only` marker file is skipped entirely — that is how a
# skill carrying private or work data stays off a public mirror. The marker lives
# in the skill, so this repo never has to name it.
rm -rf "$REPO/claude/skills"
mkdir -p "$REPO/claude/skills"
: > "$REPO/claude/skills/SYMLINKS.txt"
for d in "$CLAUDE_DIR"/skills/*/; do
  [ -e "$d" ] || continue
  name="$(basename "$d")"
  link="${d%/}"
  if [ -e "$link/.local-only" ]; then
    continue
  elif [ -L "$link" ]; then
    printf '%s -> %s\n' "$name" "$(readlink "$link")" >> "$REPO/claude/skills/SYMLINKS.txt"
  else
    cp -r "$link" "$REPO/claude/skills/$name"
  fi
done
[ -s "$REPO/claude/skills/SYMLINKS.txt" ] || rm -f "$REPO/claude/skills/SYMLINKS.txt"

# Skills that live under ~/.agents/skills (shared with other agent tools)
if [ -d "$AGENTS_DIR/skills" ]; then
  rm -rf "$REPO/claude/agents-skills"
  mkdir -p "$REPO/claude/agents-skills"
  cp -r "$AGENTS_DIR/skills/." "$REPO/claude/agents-skills/" 2>/dev/null
  find "$REPO/claude/agents-skills" -name '.local-only' -printf '%h\0' 2>/dev/null | xargs -0 -r rm -rf
  copy "$AGENTS_DIR/.skill-lock.json" "$REPO/claude/agents-skills/.skill-lock.json"
fi

# --- VS Code ---------------------------------------------------------------
copy "$VSC_USER/settings.json"    "$REPO/vscode/settings.json"
copy "$VSC_USER/keybindings.json" "$REPO/vscode/keybindings.json"
copy "$HOME/.vscode/custom-terminal-scrollbar.css" "$REPO/vscode/custom-terminal-scrollbar.css"

if [ -x "$VSC_CLI" ]; then
  "$VSC_CLI" --list-extensions > "$REPO/vscode/extensions.txt" 2>/dev/null
fi

# Snippets, if any
if [ -d "$VSC_USER/snippets" ] && [ -n "$(ls -A "$VSC_USER/snippets" 2>/dev/null)" ]; then
  rm -rf "$REPO/vscode/snippets"; mkdir -p "$REPO/vscode/snippets"
  cp -r "$VSC_USER/snippets/." "$REPO/vscode/snippets/"
fi

# --- Redact public IPs -----------------------------------------------------
# The repo is public. Strip routable IPv4 addresses from the synced copies so
# server addresses do not leak. Loopback and LAN ranges stay; they are harmless.
redact_public_ips() {
  local files
  files=$(grep -rlIE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "$REPO/claude" "$REPO/vscode" 2>/dev/null)
  [ -n "$files" ] || return 0
  echo "$files" | tr '\n' '\0' | xargs -0 perl -pi -e 's{(?<![\d.])(?!(?:0|10|127)\.)(?!192\.168\.)(?!169\.254\.)(?!172\.(?:1[6-9]|2[0-9]|3[01])\.)\d{1,3}(?:\.\d{1,3}){3}(?![\d.])}{REDACTED-IP}g'
}
redact_public_ips

# --- Commit + push ---------------------------------------------------------
cd "$REPO" || exit 1

# Never let a credential file slip in.
git rm --cached -q --ignore-unmatch '*gh-credentials*' '*.token' 2>/dev/null

if [ -z "$(git status --porcelain)" ]; then
  echo "sync: no changes"
  exit 0
fi

git add -A

# Last gate before anything is written to a public repo. The redaction above is
# text-and-IPv4 only, so this catches what it cannot: credentials pasted into a
# settings or skill file, and binary files (an image can hold anything, and
# grep -I skips it). Anything flagged aborts the commit — nothing is published
# by accident. Unstage the file, or mark its skill `.local-only`, then re-run.
guard_or_abort() {
  local bad=0 hits binaries
  hits=$(git diff --cached -U0 -G'.' \
    | grep -nE '(ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|BEGIN [A-Z ]*PRIVATE KEY' \
    | head -5)
  if [ -n "$hits" ]; then
    echo "sync: ABORTED — possible credential in the staged changes:"
    echo "$hits"
    bad=1
  fi
  binaries=$(git diff --cached --name-only --diff-filter=ACM | while read -r f; do
    [ -f "$f" ] && ! grep -Iq . "$f" && echo "$f"
  done)
  if [ -n "$binaries" ]; then
    echo "sync: ABORTED — binary file(s) staged, review before publishing:"
    echo "$binaries"
    bad=1
  fi
  [ "$bad" -eq 0 ] || { git reset -q; exit 1; }
}
guard_or_abort

git commit -q -m "sync: capture Claude Code + VS Code config $(date +%Y-%m-%d\ %H:%M)"
if git remote get-url origin >/dev/null 2>&1; then
  git push -q origin HEAD && echo "sync: pushed" || echo "sync: commit ok, push failed"
else
  echo "sync: committed (no remote configured)"
fi
