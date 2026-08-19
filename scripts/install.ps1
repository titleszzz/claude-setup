<#
  Restore this Claude Code + VS Code setup on a Windows machine.

  Usage (from the repo root):
      powershell -ExecutionPolicy Bypass -File scripts\install.ps1

  Options:
      -SkipPersonalSkills   Do not install the machine-specific skills
                            (rename-movies).
      -SkipVSCode           Only do the Claude Code side.
      -Force                Overwrite existing config files without backing up.

  Everything is copied, nothing is deleted. Existing files are backed up to
  <file>.bak.<yyyyMMdd-HHmmss> unless -Force is given.
#>

param(
    [switch]$SkipPersonalSkills,
    [switch]$SkipVSCode,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Repo      = Split-Path -Parent $PSScriptRoot
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$AgentsDir = Join-Path $env:USERPROFILE '.agents'
$VscUser   = Join-Path $env:APPDATA 'Code\User'
$PersonalSkills = @('rename-movies')

function Say($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }

function Install-File($src, $dst) {
    if (-not (Test-Path $src)) { return }
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ((Test-Path $dst) -and -not $Force) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $dst "$dst.bak.$stamp"
        Write-Host "    backed up $dst"
    }
    Copy-Item $src $dst -Force
    Write-Host "    $dst"
}

# ---------------------------------------------------------------- prereqs ---
Say 'Checking prerequisites'
foreach ($exe in 'git', 'node') {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Warn "$exe not found. Install it first (git: https://git-scm.com, node: https://nodejs.org)."
    }
}
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
    Warn 'Claude Code CLI not found. Install it with:  npm install -g @anthropic-ai/claude-code'
    Warn 'Then re-run this script so the plugin steps can run.'
}

# ----------------------------------------------------------- claude config ---
Say 'Installing Claude Code config'
Install-File (Join-Path $Repo 'claude\CLAUDE.md')             (Join-Path $ClaudeDir 'CLAUDE.md')
Install-File (Join-Path $Repo 'claude\settings.json')         (Join-Path $ClaudeDir 'settings.json')
Install-File (Join-Path $Repo 'claude\skills-lock.json')      (Join-Path $ClaudeDir 'skills-lock.json')
Install-File (Join-Path $Repo 'claude\statusline-command.sh') (Join-Path $ClaudeDir 'statusline-command.sh')
Install-File (Join-Path $Repo 'claude\keybindings.json')      (Join-Path $ClaudeDir 'keybindings.json')

# settings.json and CLAUDE.md store absolute paths from the machine they came
# from: the status line script, and the sync hook that points back at this repo.
# Rewrite both for this machine.
$slashClaude = $ClaudeDir -replace '\\', '/'
$slashRepo   = $Repo -replace '\\', '/'

$settingsPath = Join-Path $ClaudeDir 'settings.json'
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw
    $raw = [regex]::Replace($raw, 'bash [A-Za-z]:/[^"]*statusline-command\.sh', "bash $slashClaude/statusline-command.sh")
    $raw = [regex]::Replace($raw, 'bash [A-Za-z]:/[^"]*scripts/sync\.sh',       "bash $slashRepo/scripts/sync.sh")
    Set-Content -Path $settingsPath -Value $raw -Encoding utf8
    Say 'Rewrote machine-specific paths in settings.json'
}

$claudeMd = Join-Path $ClaudeDir 'CLAUDE.md'
if (Test-Path $claudeMd) {
    $raw = Get-Content $claudeMd -Raw
    $raw = [regex]::Replace($raw, 'bash [A-Za-z]:/[^\s]*scripts/sync\.sh', "bash $slashRepo/scripts/sync.sh")
    $raw = [regex]::Replace($raw, '`[A-Za-z]:\\[^`]*claude-setup`', "``$Repo``")
    Set-Content -Path $claudeMd -Value $raw -Encoding utf8
    Say 'Rewrote the setup-repo path in CLAUDE.md'
}

Say 'Installing skills'
$skillSrc = Join-Path $Repo 'claude\skills'
if (Test-Path $skillSrc) {
    $skillDst = Join-Path $ClaudeDir 'skills'
    if (-not (Test-Path $skillDst)) { New-Item -ItemType Directory -Force -Path $skillDst | Out-Null }
    Get-ChildItem $skillSrc -Directory | ForEach-Object {
        if ($SkipPersonalSkills -and ($PersonalSkills -contains $_.Name)) {
            Write-Host "    skipped (personal): $($_.Name)"
            return
        }
        Copy-Item $_.FullName (Join-Path $skillDst $_.Name) -Recurse -Force
        Write-Host "    $($_.Name)"
    }
}

# Skills shared with other agent tools live under ~/.agents/skills and are
# symlinked into ~/.claude/skills. Copy them, then link.
$agentsSrc = Join-Path $Repo 'claude\agents-skills'
if (Test-Path $agentsSrc) {
    Say 'Installing ~/.agents skills'
    New-Item -ItemType Directory -Force -Path (Join-Path $AgentsDir 'skills') | Out-Null
    Get-ChildItem $agentsSrc -Directory | ForEach-Object {
        $name   = $_.Name          # $_ becomes the error record inside catch, so grab it now
        $target = Join-Path $AgentsDir "skills\$name"
        Copy-Item $_.FullName $target -Recurse -Force
        $link = Join-Path $ClaudeDir "skills\$name"
        if (-not (Test-Path $link)) {
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
            } catch {
                Copy-Item $target $link -Recurse -Force
                Warn "Symlink failed for $name (needs Developer Mode or admin) - copied instead."
            }
        }
        Write-Host "    $name"
    }
    $lock = Join-Path $agentsSrc '.skill-lock.json'
    if (Test-Path $lock) { Copy-Item $lock (Join-Path $AgentsDir '.skill-lock.json') -Force }
}

# ---------------------------------------------------------------- plugins ---
if ($claude) {
    Say 'Adding plugin marketplaces'
    $mk = Get-Content (Join-Path $Repo 'claude\plugins\known_marketplaces.json') -Raw | ConvertFrom-Json
    foreach ($name in $mk.PSObject.Properties.Name) {
        $repoRef = $mk.$name.source.repo
        if ($repoRef) {
            Write-Host "    $name  ($repoRef)"
            & claude plugin marketplace add $repoRef 2>&1 | Out-Null
        }
    }

    Say 'Installing plugins'
    $ip = Get-Content (Join-Path $Repo 'claude\plugins\installed_plugins.json') -Raw | ConvertFrom-Json
    foreach ($id in $ip.plugins.PSObject.Properties.Name) {
        Write-Host "    $id"
        & claude plugin install $id 2>&1 | Out-Null
    }
    Say 'Plugin install done. Check with:  claude plugin list'
} else {
    Warn 'Skipping plugin install - Claude Code CLI missing.'
}

# ----------------------------------------------------------------- vscode ---
if (-not $SkipVSCode) {
    Say 'Installing VS Code config'
    Install-File (Join-Path $Repo 'vscode\settings.json')    (Join-Path $VscUser 'settings.json')
    Install-File (Join-Path $Repo 'vscode\keybindings.json') (Join-Path $VscUser 'keybindings.json')
    Install-File (Join-Path $Repo 'vscode\custom-terminal-scrollbar.css') (Join-Path $env:USERPROFILE '.vscode\custom-terminal-scrollbar.css')

    $snip = Join-Path $Repo 'vscode\snippets'
    if (Test-Path $snip) { Copy-Item $snip (Join-Path $VscUser 'snippets') -Recurse -Force }

    # settings.json points vscode_custom_css.imports at the old user's path.
    $vsSettings = Join-Path $VscUser 'settings.json'
    if (Test-Path $vsSettings) {
        $raw = Get-Content $vsSettings -Raw
        $cssPath = Join-Path $env:USERPROFILE '.vscode\custom-terminal-scrollbar.css'
        $cssUri = 'file:///' + ($cssPath -replace '\\', '/')
        $raw = [regex]::Replace($raw, 'file:///[A-Za-z]:/[^"]*custom-terminal-scrollbar\.css', $cssUri)
        Set-Content -Path $vsSettings -Value $raw -Encoding utf8
        Say 'Rewrote the custom CSS path in VS Code settings.json'
    }

    $codeCmd = $null
    $found = Get-Command code -ErrorAction SilentlyContinue
    if ($found) {
        $codeCmd = $found.Source
    } else {
        $guess = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
        if (Test-Path $guess) { $codeCmd = $guess }
    }
    if ($codeCmd) {
        Say 'Installing VS Code extensions'
        Get-Content (Join-Path $Repo 'vscode\extensions.txt') | Where-Object { $_.Trim() } | ForEach-Object {
            Write-Host "    $_"
            & $codeCmd --install-extension $_ --force 2>&1 | Out-Null
        }
    } else {
        Warn 'VS Code CLI not found - install extensions manually from vscode\extensions.txt'
    }

    Warn 'Custom CSS needs one manual step: run VS Code as Administrator, open the'
    Warn 'Command Palette and run "Enable Custom CSS and JS", then restart VS Code.'
}

Say 'Done. Restart VS Code and start a new Claude Code session.'
