---
name: rtk
description: Show RTK (Rust Token Killer) token-savings analytics. Trigger on /rtk. Bare /rtk runs `rtk gain`; /rtk history runs `rtk gain --history`; /rtk discover runs `rtk discover`. Any other argument is passed straight through to `rtk`.
---

# rtk

A shortcut for RTK's own analytics. When invoked:

- `/rtk` (no argument) — run `rtk gain`
- `/rtk history` — run `rtk gain --history`
- `/rtk discover` — run `rtk discover`
- `/rtk <anything else>` — run `rtk <anything else>` verbatim

Steps:

1. Run the matching command with the Bash tool, exactly as above. Do not add flags the user did not ask for.
2. Show the command's output. `rtk gain` prints a savings table — relay it as-is; do not reformat the numbers or invent totals it did not print.
3. If the command fails with "command not found", tell the user RTK is not on PATH here (see `~/.claude/RTK.md` — a name collision with a different `rtk` is the usual cause) rather than guessing at numbers.

Keep it to the output plus a one-line read of it. This skill only reports; it changes nothing.
