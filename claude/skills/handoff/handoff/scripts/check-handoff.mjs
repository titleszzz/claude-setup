#!/usr/bin/env node
// Validate this project's handoff-state.md: is it well-formed, is it stale, and
// does what it claims about git still match reality?
//
// Usage:  node check-handoff.mjs [cwd] [--verbose]
// Output: one line per check. WARN = trust it less. FAIL = it is broken.
// Exit:   0 = no FAIL (warnings allowed), 1 = at least one FAIL, 2 = no note.

import { existsSync, readFileSync, statSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { homedir } from 'node:os'

const args = process.argv.slice(2)
const verbose = args.includes('--verbose')
const cwd = args.find((a) => !a.startsWith('--')) || process.cwd()

const slug = cwd.replace(/[^A-Za-z0-9]/g, '-')
const dir = `${homedir()}/.claude/projects/${slug}/memory`
const file = `${dir}/handoff-state.md`
const memFile = `${dir}/MEMORY.md`

const out = []
const ok = (m) => out.push(['OK', m])
const warn = (m) => out.push(['WARN', m])
const fail = (m) => out.push(['FAIL', m])

const report = (code) => {
  const shown = out.filter(([lvl]) => verbose || lvl !== 'OK')
  if (shown.length) {
    console.log(`handoff check: ${file}`)
    for (const [lvl, m] of shown) console.log(`  ${lvl}: ${m}`)
  } else {
    console.log(`handoff check: ${file} — all checks passed`)
  }
  process.exit(code)
}

if (!existsSync(file)) {
  console.log(`handoff check: no note for ${cwd} (expected ${file})`)
  process.exit(2)
}

const text = readFileSync(file, 'utf8')

// --- structure -------------------------------------------------------------
const fm = text.match(/^---\n([\s\S]*?)\n---\n/)
if (!fm) {
  fail('no YAML frontmatter block — memory loader will not index this file')
} else {
  const body = fm[1]
  if (!/^name:\s*handoff-state\s*$/m.test(body)) fail('frontmatter missing "name: handoff-state"')
  else ok('frontmatter name')
  if (!/^description:\s*\S/m.test(body)) fail('frontmatter missing a description')
  else ok('frontmatter description')
  if (!/^\s+type:\s*project\s*$/m.test(body)) warn('frontmatter metadata.type is not "project"')
  else ok('frontmatter metadata.type')
}

const has = (s) => text.includes(s)
const autoShape = has('**Last things I was asked to do:**')
const manualShape = has('## What I was doing') && has('## Half-done') && has('## Next step')

if (!autoShape && !manualShape) {
  fail('note matches neither shape — not the auto hook output, not a complete /handoff note')
} else if (autoShape) {
  ok('auto shape (PreCompact hook output)')
  warn('mechanical note only — no "what was half-done" or "next step". Run /handoff for those.')
} else {
  ok('manual shape (full /handoff note)')
}

for (const field of ['**Branch:**', '**Uncommitted:**']) {
  if (!has(field)) fail(`missing ${field} line`)
  else ok(`${field} present`)
}

// --- staleness -------------------------------------------------------------
const ageDays = Math.floor((Date.now() - statSync(file).mtimeMs) / 86400000)
if (ageDays >= 14) warn(`note is ${ageDays} days old — probably describes work you have moved on from`)
else if (ageDays >= 7) warn(`note is ${ageDays} days old`)
else ok(`written ${ageDays}d ago`)

// --- drift against live git ------------------------------------------------
const git = (...a) => {
  try {
    return execFileSync('git', ['-C', cwd, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    return ''
  }
}
const liveBranch = git('rev-parse', '--abbrev-ref', 'HEAD')

if (!liveBranch) {
  ok('not a git repo — nothing to compare')
} else {
  const noted = (text.match(/\*\*Branch:\*\*\s*(.+)/) || [])[1]?.trim()
  if (!noted) {
    warn('cannot read the recorded branch to compare')
  } else if (noted === liveBranch) {
    ok(`branch still ${liveBranch}`)
  } else {
    warn(`branch drifted: note says "${noted}", you are on "${liveBranch}"`)
  }

  // Uncommitted list: the note records paths, git reports "XY path".
  const liveDirty = new Set(
    git('status', '--porcelain').split('\n').filter(Boolean).map((l) => l.slice(3).trim()),
  )
  const notedBlock = (text.match(/\*\*Uncommitted:\*\*\s*\n([\s\S]*?)\n\s*\n/) || [])[1] || ''
  const notedDirty = new Set(
    notedBlock.split('\n').map((l) => l.replace(/^[-*]\s*/, '').slice(0, 200).trim()).filter((l) => l && l !== 'clean' && l !== 'n/a'),
  )
  const gone = [...notedDirty].filter((f) => !liveDirty.has(f) && !liveDirty.has(f.slice(3).trim()))
  const fresh = [...liveDirty].filter((f) => !notedDirty.has(f) && ![...notedDirty].some((n) => n.endsWith(f)))
  if (gone.length) warn(`${gone.length} file(s) the note lists as uncommitted are now clean or committed: ${gone.slice(0, 5).join(', ')}`)
  if (fresh.length) warn(`${fresh.length} file(s) changed since the note was written: ${fresh.slice(0, 5).join(', ')}`)
  if (!gone.length && !fresh.length) ok('uncommitted files still match')
}

// --- MEMORY.md pointer -----------------------------------------------------
if (!existsSync(memFile)) {
  warn('no MEMORY.md in this project — the note will not be surfaced by the memory index')
} else {
  const ptrs = readFileSync(memFile, 'utf8').split('\n').filter((l) => l.startsWith('- [Session handoff]'))
  if (ptrs.length === 0) warn('MEMORY.md has no pointer line for the handoff note')
  else if (ptrs.length > 1) fail(`MEMORY.md has ${ptrs.length} handoff pointer lines — should be exactly one`)
  else ok('MEMORY.md pointer')
}

report(out.some(([lvl]) => lvl === 'FAIL') ? 1 : 0)
