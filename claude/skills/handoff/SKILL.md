---
name: handoff
description: Save or restore a session handoff note — what I was working on, what is half-done, what comes next — so a fresh session (or one after auto-compact) picks up without re-explaining. Writes to the current project's memory dir as handoff-state.md and indexes it in MEMORY.md. Trigger on /handoff, /handoff save, /handoff resume, and whenever the user says they are about to run out of context, wants to hand off, wrap up, checkpoint, or asks "where were we".
---

# Handoff

Two modes. Default is **save**.

- `/handoff` or `/handoff save` — write the current state out.
- `/handoff resume` — read it back and brief the user.

## Where the file lives

Run the helper to get the path (it creates the directory if missing):

```bash
bash ~/.claude/skills/handoff/scripts/handoff-path.sh
```

It prints `~/.claude/projects/<encoded-cwd>/memory/handoff-state.md`.
Never guess this path — the encoding is not obvious. Always run the script.

## Save

1. Get the path from the helper.
2. Gather facts. Do not invent any of these — if a command fails or the project is not a git repo, write "n/a".
   - `git rev-parse --abbrev-ref HEAD` — current branch
   - `git status --porcelain` — uncommitted / untracked files
   - `git log --oneline -5` — recent commits
   - Whatever is in the current todo list, if one is active.
3. Overwrite the file with exactly this shape:

```markdown
---
name: handoff-state
description: Session handoff — where work stood as of <YYYY-MM-DD>, on branch <branch>. Read this before starting new work in this project.
metadata:
  type: project
---

# Handoff — <YYYY-MM-DD HH:MM>

**Branch:** <branch>
**Uncommitted:** <file list, or "clean">
**Recent commits:**
- <sha> <subject>

## What I was doing
<2-4 plain sentences. The actual task, not a summary of the repo.>

## Half-done
<Anything started but not finished: a file mid-edit, a failing test, a migration applied but not verified. Say exactly what state it is in. If nothing, write "nothing in flight".>

## Next step
<The single next action, concrete enough to act on without asking.>

## Watch out for
<Traps found this session: a flaky command, a path that needs quoting, a service that must be restarted. Omit the section if empty.>
```

4. Add or update the pointer line in the same directory's `MEMORY.md`:
   `- [Session handoff](handoff-state.md) — where work stood on <branch>, <YYYY-MM-DD>`
   One line only. If a pointer already exists, replace it, do not add a second.
5. Tell the user the file path and a one-line summary of what was saved.

Overwrite every time. There is no history — one file, latest state.

## Resume

1. Get the path from the helper. If the file does not exist, say so and stop.
2. Read it.
3. **Check it is still true before trusting it.** Compare the recorded branch and uncommitted files against `git status` now. If they disagree, say which parts are stale and treat those as unknown.
4. Brief the user: what they were doing, what is half-done, the next step. Short. Then ask if that is still the plan before acting on it.

## Notes

- This is a manual command. Claude cannot see its own context percentage and cannot fire this at a threshold. To run it automatically before auto-compaction, register a `PreCompact` hook in `~/.claude/settings.json`.
- Keep the file honest. A handoff note that overstates progress is worse than none.
