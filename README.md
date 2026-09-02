# claude-setup

My whole Claude Code + VS Code setup on Windows, in one repo.

Use it to:

- rebuild this machine after a fresh Windows install,
- hand the same setup to a friend,
- keep a versioned history of every skill / plugin / setting change.

Everything here is captured from a real working machine by `scripts/sync.sh`,
and put back by `scripts/install.ps1`.

---

## 1. What's inside

```
claude/
  CLAUDE.md                  global instructions Claude follows in every project
  settings.json              global Claude Code settings (status line, plugins, hooks)
                             note: the `autoMode` block is stripped before commit,
                             it names private projects. Re-add it on a new machine.
  statusline-command.sh      the custom status line script (model, dir, 5h/7d usage bars)
  skills-lock.json           which GitHub repo each installed skill came from
  skills/                    the actual skill folders
  agents-skills/             skills that live in ~/.agents/skills and are symlinked in
  plugins/
    installed_plugins.json   which plugins are installed, and at which commit
    known_marketplaces.json  which plugin marketplaces are registered
vscode/
  settings.json              VS Code user settings
  keybindings.json           VS Code keybindings
  extensions.txt             one extension id per line
  custom-terminal-scrollbar.css   always-visible fat terminal scrollbar
scripts/
  install.ps1                restore all of this onto a Windows machine
  sync.sh                    capture the live config back into this repo + push
```

### Plugins

Installed from marketplaces, so they update themselves.

| Plugin | Marketplace (GitHub repo) | What it does |
|---|---|---|
| `caveman@caveman` | `JuliusBrussee/caveman` | Terse "caveman" answer style. Cuts filler words, keeps all technical content. Adds `/caveman`, `/caveman-commit`, `/caveman-review`, `/caveman-stats`, and the `cavecrew-*` subagents. |
| `andrej-karpathy-skills@karpathy-skills` | `multica-ai/andrej-karpathy-skills` | Coding discipline rules — surgical changes, no overcomplication, verifiable success criteria. |
| `i-have-adhd@i-have-adhd` | `ayghri/i-have-adhd` | Focus / task-nudging helpers. |

The official marketplace `anthropics/claude-plugins-official` is also registered
(nothing installed from it yet).

### Skills

| Skill | Where it comes from | What it does |
|---|---|---|
| `debug-mantra` | `thananon/9arm-skills` | Four-step debugging discipline: reproduce, trace the fail path, falsify the hypothesis, cross-check breadcrumbs. Fires automatically when you report a bug. |
| `scrutinize` | `thananon/9arm-skills` | Outsider review of a plan, PR or diff. Asks "is there a simpler way" first, then traces the real code path. |
| `find-skills` | `~/.agents/skills`, symlinked in | Finds and installs new skills when you ask "is there a skill for X". |
| `rename-movies` | hand-written, personal | Renames episode files on the Pi's `WD_Movies` share to `ep1..epN` over SSH. **Only useful with that Pi.** |

The personal ones can be skipped with `-SkipPersonalSkills`.

Some skills on this machine are **not mirrored here at all**. Any skill folder
holding a `.local-only` marker file is skipped by `sync.sh` — that is how a skill
carrying work or private data stays off a public repo. Those skills live only on
the machine that made them, so back them up separately.

Binary assets that ship inside a skill — fonts, audio, images, video, archives —
are ignored by `.gitignore` and never reach this repo. They are stock files that
come back when the skill is reinstalled, so the mirror stays text-only: a smaller
repo, no third-party media redistributed, and nothing for the binary guard in
`scripts/sync.sh` to trip over. A restore therefore needs the skill reinstalled,
not just this repo copied.

### VS Code

| Setting | Why |
|---|---|
| `vscode_custom_css.imports` + `custom-terminal-scrollbar.css` | **The sliding scrollbar.** VS Code hides the terminal scrollbar until you hover. This CSS forces it always visible, 14px wide, rounded, grey. Needs the `be5invis.vscode-custom-css` extension. |
| `workbench.colorCustomizations.scrollbarSlider.*` | Makes the normal editor scrollbar slider brighter and easier to grab. |
| `terminal.integrated.smoothScrolling: true` | Terminal scrolls smoothly instead of jumping line by line. |
| `terminal.integrated.mouseWheelScrollSensitivity: 3` | Faster wheel scrolling in the terminal. |
| `terminal.integrated.scrollback: 20000` | Long Claude sessions stay scrollable. |
| `terminal.integrated.gpuAcceleration: "off"` | Fixes flicker / missing glyphs with Claude Code's redraws. |
| `terminal.integrated.env.windows.CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN: "1"` | Keeps Claude output in the normal scrollback buffer, so you can scroll back after it exits. |
| `claudeCode.useTerminal: true` | Run Claude Code in the integrated terminal, not a webview. |
| `shift+enter` keybinding | Sends `ESC + CR` to the terminal, which Claude Code reads as "newline, don't submit". |
| `terminal.integrated.enableMultiLinePasteWarning: "never"` | No nag when pasting multi-line prompts. |
| `remote.SSH.remotePlatform` | Marks the Pi and the karaoke server as Linux so Remote-SSH connects without asking. |

### The Claude status bar

`claude/statusline-command.sh` is the status line at the bottom of every Claude
session. It shows:

```
Opus 5 | karaoke_app | 5h ████░░░░░░  38% ⏳ 2h 14m | 7d ██░░░░░░░░  21% ⏳ 4d 6h
```

- model name, then the current folder,
- a colour bar for the 5-hour usage limit and one for the 7-day limit
  (green → yellow at 70% → red at 90%),
- a countdown to when each limit resets.

It parses the JSON Claude Code feeds it with plain `grep -oP` and `sed` — no `jq`
needed, so it works out of the box in Git Bash on Windows. It is wired up in
`claude/settings.json` under `statusLine`.

---

## 2. Install — the fast way

On a fresh Windows box:

```powershell
# prerequisites
winget install Git.Git
winget install OpenJS.NodeJS.LTS
winget install Microsoft.VisualStudioCode
npm install -g @anthropic-ai/claude-code

# get this repo
git clone https://github.com/titleszzz/claude-setup.git
cd claude-setup

# put everything in place
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

Useful flags:

```powershell
# skip my ship / Pi specific skills (what a friend usually wants)
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipPersonalSkills

# Claude Code only, leave VS Code alone
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -SkipVSCode
```

The script never deletes anything. Any file it would overwrite is copied to
`<file>.bak.<timestamp>` first, unless you pass `-Force`.

Then finish two manual bits:

1. `claude` → log in with your own Anthropic account. **No credentials are in this repo.**
2. Enable the custom CSS (see step 3.5 below) — that's the only part Windows
   won't let a script do.

---

## 3. Install — the manual way

If you'd rather do it by hand, or the script fails halfway.

### 3.1 Prerequisites

| Thing | Install |
|---|---|
| Git for Windows | `winget install Git.Git` — also gives you Git Bash, which the status line needs |
| Node.js LTS | `winget install OpenJS.NodeJS.LTS` |
| VS Code | `winget install Microsoft.VisualStudioCode` |
| Claude Code | `npm install -g @anthropic-ai/claude-code` |

Log in once: run `claude` in any folder and follow the browser prompt.

### 3.2 Copy the Claude Code config

```powershell
$src = "<path to this repo>"
copy "$src\claude\CLAUDE.md"             "$env:USERPROFILE\.claude\CLAUDE.md"
copy "$src\claude\settings.json"         "$env:USERPROFILE\.claude\settings.json"
copy "$src\claude\skills-lock.json"      "$env:USERPROFILE\.claude\skills-lock.json"
copy "$src\claude\statusline-command.sh" "$env:USERPROFILE\.claude\statusline-command.sh"
```

Then open `~/.claude/settings.json` and fix the status line path so it points at
**your** user folder:

```json
"statusLine": {
  "type": "command",
  "command": "bash C:/Users/<YOUR-NAME>/.claude/statusline-command.sh"
}
```

Fix the sync hook path in the same file, so it points at wherever you cloned
this repo:

```json
"hooks": {
  "SessionEnd": [
    { "hooks": [ { "type": "command",
                   "command": "bash <PATH-TO-THIS-REPO>/scripts/sync.sh",
                   "timeout": 60 } ] }
  ]
}
```

Same path appears once more, near the bottom of `~/.claude/CLAUDE.md`. Fix it
there too, or delete that section if you don't want auto-sync.
(`install.ps1` rewrites all three of these for you.)

### 3.3 Add the marketplaces and install the plugins

```powershell
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add multica-ai/andrej-karpathy-skills
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add ayghri/i-have-adhd

claude plugin install andrej-karpathy-skills@karpathy-skills
claude plugin install caveman@caveman
claude plugin install i-have-adhd@i-have-adhd

claude plugin list        # check
```

A plugin is enabled/disabled by the `enabledPlugins` block in
`~/.claude/settings.json`, which step 3.2 already copied. You can also toggle
them with `claude plugin enable <id>` / `claude plugin disable <id>`, or the
`/plugin` command inside a session.

### 3.4 Install the skills

Skills are just folders. Copy them:

```powershell
xcopy /E /I /Y "$src\claude\skills" "$env:USERPROFILE\.claude\skills"
```

`find-skills` normally lives in `~/.agents/skills/find-skills` and is symlinked
into `~/.claude/skills`. To reproduce that:

```powershell
xcopy /E /I /Y "$src\claude\agents-skills" "$env:USERPROFILE\.agents\skills"
New-Item -ItemType SymbolicLink `
  -Path   "$env:USERPROFILE\.claude\skills\find-skills" `
  -Target "$env:USERPROFILE\.agents\skills\find-skills"
```

Symlinks need Windows Developer Mode on, or an admin shell. If that's a hassle,
just copy the folder instead — it works the same, it only stops the two agent
tools sharing one copy.

`skills-lock.json` records that `debug-mantra` and `scrutinize` came from
`thananon/9arm-skills`, so they can be re-fetched or updated later.

Check everything loaded: start `claude` and type `/` — the skills appear as
slash commands.

### 3.5 VS Code

```powershell
copy "$src\vscode\settings.json"    "$env:APPDATA\Code\User\settings.json"
copy "$src\vscode\keybindings.json" "$env:APPDATA\Code\User\keybindings.json"
copy "$src\vscode\custom-terminal-scrollbar.css" "$env:USERPROFILE\.vscode\custom-terminal-scrollbar.css"

Get-Content "$src\vscode\extensions.txt" | ForEach-Object { code --install-extension $_ }
```

Then edit `%APPDATA%\Code\User\settings.json` and point the CSS import at your
own user folder:

```json
"vscode_custom_css.imports": [
  "file:///C:/Users/<YOUR-NAME>/.vscode/custom-terminal-scrollbar.css"
]
```

**Turn on the custom CSS (the always-visible terminal scrollbar):**

1. Close VS Code.
2. Reopen it **as Administrator** (right-click → Run as administrator).
   The extension has to patch VS Code's own files, which needs write access to
   the install folder.
3. `Ctrl+Shift+P` → **Enable Custom CSS and JS**.
4. It warns that VS Code is now "corrupted" / unsupported — that's normal for
   this extension. Click through it.
5. Restart VS Code.

Redo those steps after every VS Code update, because the update overwrites the
patch. If the scrollbar disappears, that's why.

### 3.6 Things this repo deliberately does NOT contain

- Anthropic login / API keys — you log in yourself.
- GitHub tokens (`.gitignore` blocks `*gh-credentials*`, `*.token`).
- `~/.claude/projects/` — session history and per-project memory.
- Plugin source code — it's re-downloaded from each marketplace.

---

## 4. Auto-sync

Whenever a skill or plugin is added, removed, enabled or disabled, this repo
should be updated. Two ways that happens:

**Automatic.** `~/.claude/settings.json` has a `SessionEnd` hook that runs
`scripts/sync.sh`. It copies the live config into the repo, and commits +
pushes only if something actually changed. Nothing changed → it prints
`sync: no changes` and exits.

**Manual.** Any time:

```bash
bash /e/Claude_libary/claude-setup/scripts/sync.sh
```

`~/.claude/CLAUDE.md` also carries a standing instruction telling Claude to run
that script after touching any global skill, plugin, setting, or VS Code config.

To point the sync at your own GitHub instead of mine:

```bash
cd claude-setup
git remote set-url origin https://github.com/<you>/claude-setup.git
```

---

## 5. Troubleshooting

| Symptom | Fix |
|---|---|
| Status line is blank | The `statusLine.command` path in `~/.claude/settings.json` still points at the old user folder. Fix the path. Also check `bash --version` works — it needs Git Bash. |
| Status line shows model + dir but no usage bars | Normal on API-key billing. The 5h/7d bars only appear for Claude.ai subscription accounts. |
| Terminal scrollbar back to auto-hide | VS Code updated and wiped the CSS patch. Redo step 3.5. |
| `shift+enter` submits instead of adding a newline | `keybindings.json` didn't get copied, or another extension grabbed the key. |
| Plugin commands missing after install | Restart the Claude session. Confirm with `claude plugin list` and check `enabledPlugins` in `~/.claude/settings.json`. |
| `claude plugin marketplace add` fails | Needs `git` on PATH and network access to github.com. |
| Skills don't show up as `/commands` | They must sit at `~/.claude/skills/<name>/SKILL.md` — one folder per skill, with YAML frontmatter containing `name:` and `description:`. |
| Symlink creation fails | Turn on Windows Developer Mode (Settings → System → For developers), or just copy the folder. |
