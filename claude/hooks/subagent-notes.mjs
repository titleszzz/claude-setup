#!/usr/bin/env node
// SubagentStop hook — makes "write down what you learned" automatic.
//
// When a subagent finishes, this checks whether it wrote anything into the
// project's `.claude/agent-notes/<agent>.md`. If it did, the hook stays out of
// the way. If it did not, it blocks the stop once and hands the agent an
// instruction to record what it learned, then let it finish.
//
// Deliberately narrow, so it can never fire on an unrelated subagent:
//   - only when the payload names an agent type (`agent_type`), and
//   - only when that project already has `.claude/agent-notes/<agent_type>.md`.
// Anything else exits 0 silently. It also exits 0 on any error, and honours
// `stop_hook_active`, so it can block at most once per subagent and can never
// take a run down.
import { appendFileSync, existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'

const LOG = join(homedir(), '.claude', 'hooks', 'subagent-notes.log')
const log = (msg) => {
  try {
    appendFileSync(LOG, `${new Date().toISOString()} ${msg}\n`, 'utf8')
  } catch {}
}

const read = (s) => new Promise((res) => {
  let d = ''
  s.setEncoding('utf8')
  s.on('data', (c) => (d += c))
  s.on('end', () => res(d))
})

// Walk up from cwd looking for .claude/agent-notes/<agent>.md, so being in a
// subdirectory of the project still finds the notes file.
const findNotes = (startDir, agent) => {
  let dir = startDir
  for (let i = 0; i < 4 && dir; i++) {
    const candidate = join(dir, '.claude', 'agent-notes', `${agent}.md`)
    if (existsSync(candidate)) return candidate
    const parent = dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  return null
}

// Did this subagent already write to its notes file during the run?
const wroteNotes = (transcriptPath) => {
  if (!transcriptPath || !existsSync(transcriptPath)) return false
  let lines
  try {
    lines = readFileSync(transcriptPath, 'utf8').split('\n')
  } catch {
    return false
  }
  for (const line of lines) {
    if (!line.includes('agent-notes')) continue
    let e
    try { e = JSON.parse(line) } catch { continue }
    const content = e?.message?.content
    if (!Array.isArray(content)) continue
    for (const block of content) {
      if (block?.type !== 'tool_use') continue
      const name = block.name || ''
      const input = block.input || {}
      if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(name)) {
        if (String(input.file_path || '').includes('agent-notes')) return true
      }
      if (name === 'Bash') {
        const cmd = String(input.command || '')
        if (cmd.includes('agent-notes') && /(>>|>|tee\b)/.test(cmd)) return true
      }
    }
  }
  return false
}

const countLines = (file) => {
  try {
    return readFileSync(file, 'utf8').split('\n').length
  } catch {
    return 0
  }
}

try {
  const input = JSON.parse((await read(process.stdin)) || '{}')

  // Already blocked once for this subagent — never block twice.
  if (input.stop_hook_active) process.exit(0)

  const agent = String(input.agent_type || '').trim()
  if (!agent) process.exit(0)

  const cwd = input.cwd || process.cwd()
  const notes = findNotes(cwd, agent)
  if (!notes) process.exit(0)

  if (wroteNotes(input.agent_transcript_path)) {
    log(`${agent}: notes already updated, nothing to do`)
    process.exit(0)
  }

  const lines = countLines(notes)
  const overCap = lines > 150
    ? ` The file is currently ${lines} lines, which is over the ~150-line cap in the README beside it — prune it in the same edit: cut duplicates, anything superseded, and anything an agent would work out in one look, and correct a wrong line rather than leaving it beside the right one.`
    : ''

  const reason = [
    `Before you finish: you did not write anything into ${notes} during this run.`,
    `That file is how the next run of ${agent} avoids rediscovering what you just worked out, so it is part of the job, not an extra.`,
    `Append what this run actually taught you — one or two lines per fact, dated ${new Date().toISOString().slice(0, 10)}:`,
    `proven shortcuts (the exact command, selector, path or tap that worked), screen coordinates with the screen size they were measured on, dead ends with their exact error string, and measured costs in credits, minutes or tool calls.`,
    `Write only what you saw work or fail; mark anything you are unsure of as "suspected". Correct a line that turned out wrong instead of adding a second one beside it. Nothing about this one product, and no secrets.${overCap}`,
    `If this run genuinely taught you nothing new, add a single dated line saying the recipe in the file worked as written.`,
    `Then repeat your final report as you would have given it.`,
  ].join(' ')

  log(`${agent}: blocked once to make it record notes in ${notes} (${lines} lines)`)
  console.log(JSON.stringify({ decision: 'block', reason }))
} catch (err) {
  log(`hook error, ignored: ${err.message}`)
}
process.exit(0)
