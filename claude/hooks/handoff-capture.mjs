#!/usr/bin/env node
// Auto-capture hook for handoff-state.md. Registered on two events:
//   PreCompact  — before context is compacted (auto or manual /compact)
//   SessionEnd  — when the session closes, so quitting also leaves a note
// Records mechanical facts only. Never blocks either event — always exits 0.
// Will not overwrite a manual /handoff note less than MANUAL_GRACE_HOURS old:
// that note has reasoning in it that this script cannot reproduce.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const read = (s) => new Promise((res) => {
  let d = ''
  s.setEncoding('utf8')
  s.on('data', (c) => (d += c))
  s.on('end', () => res(d))
})

const git = (cwd, args) => {
  try {
    return execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    return ''
  }
}

// Last N real user prompts from the transcript, so the note says what was
// actually being worked on instead of guessing.
const recentPrompts = (path, n) => {
  if (!path || !existsSync(path)) return []
  const out = []
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line.trim()) continue
    let e
    try { e = JSON.parse(line) } catch { continue }
    if (e?.type !== 'user') continue
    // Skip tool results and injected meta turns (skill bodies, hook context).
    if (e.isMeta || e.isSidechain || e.sourceToolUseID) continue
    const c = e?.message?.content
    let text = ''
    if (typeof c === 'string') text = c
    else if (Array.isArray(c)) text = c.filter((p) => p?.type === 'text').map((p) => p.text).join(' ')
    text = text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '').replace(/\s+/g, ' ').trim()
    if (!text || text.length < 3) continue
    // Slash commands are harness input, not work. Very long turns are pastes.
    // Harness turns: "<command-name>/compact</command-name>", "<local-command-stdout>…".
    if (text.startsWith('<')) continue
    if (text.startsWith('/')) continue
    if (text.length > 500) continue
    out.push(text.length > 200 ? text.slice(0, 200) + '…' : text)
  }
  return out.slice(-n)
}

try {
  const input = JSON.parse((await read(process.stdin)) || '{}')
  const cwd = input.cwd || process.cwd()
  const event = input.hook_event_name || 'unknown'
  const trigger = input.trigger || input.reason || 'unknown'
  const occasion = event === 'SessionEnd'
    ? `at session end (${trigger})`
    : `before ${trigger} compaction`

  const slug = cwd.replace(/[^A-Za-z0-9]/g, '-')
  const dir = join(homedir(), '.claude', 'projects', slug, 'memory')
  mkdirSync(dir, { recursive: true })
  const file = join(dir, 'handoff-state.md')

  const now = new Date()
  const pad = (x) => String(x).padStart(2, '0')
  const day = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
  const stamp = `${day} ${pad(now.getHours())}:${pad(now.getMinutes())}`

  // A manual /handoff note carries what was half-done and what comes next.
  // This script knows neither, so it must not clobber a fresh one.
  const MANUAL_GRACE_HOURS = 12
  if (existsSync(file)) {
    const prev = readFileSync(file, 'utf8')
    const ageHours = (Date.now() - statSync(file).mtimeMs) / 3600000
    if (prev.includes('## What I was doing') && ageHours < MANUAL_GRACE_HOURS) {
      console.log(`handoff: kept the manual note (${ageHours.toFixed(1)}h old), not overwriting it`)
      process.exit(0)
    }
  }

  const branch = git(cwd, ['rev-parse', '--abbrev-ref', 'HEAD']) || 'n/a (not a git repo)'
  const dirty = git(cwd, ['status', '--porcelain'])
  const commits = git(cwd, ['log', '--oneline', '-5'])
  const prompts = recentPrompts(input.transcript_path, 5)

  const body = `---
name: handoff-state
description: Auto-captured session handoff — where work stood on ${day}, branch ${branch}, in ${cwd}. Read before starting new work in this project; verify against git before trusting it.
metadata:
  type: project
---

# Handoff — ${stamp} (auto, ${occasion})

**Project:** ${cwd}
**Branch:** ${branch}

**Uncommitted:**
${dirty ? '```\n' + dirty + '\n```' : 'clean'}

**Recent commits:**
${commits ? '```\n' + commits + '\n```' : 'n/a'}

**Last things I was asked to do:**
${prompts.length ? prompts.map((p) => `- ${p}`).join('\n') : '- n/a'}

> Written by the auto-capture hook, not by Claude. It records mechanical facts
> only — it does not know what was half-finished or what the next step is.
> Run \`/handoff\` yourself for a note that includes that.
`

  writeFileSync(file, body, 'utf8')

  // Keep exactly one pointer line in MEMORY.md so the next session notices it.
  const memFile = join(dir, 'MEMORY.md')
  const pointer = `- [Session handoff](handoff-state.md) — auto-captured ${day}, branch ${branch}`
  let mem = existsSync(memFile) ? readFileSync(memFile, 'utf8') : ''
  const lines = mem.split('\n').filter((l) => !l.startsWith('- [Session handoff]'))
  while (lines.length && !lines[lines.length - 1].trim()) lines.pop()
  lines.push(pointer, '')
  writeFileSync(memFile, lines.join('\n'), 'utf8')

  console.log(`handoff: saved ${file}`)
} catch (err) {
  console.error(`handoff hook failed: ${err.message}`)
}
process.exit(0)
