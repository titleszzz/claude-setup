#!/usr/bin/env node
// PROBE BUILD - logs the SubagentStop payload, decides nothing yet.
import { appendFileSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const read = (s) => new Promise((res) => {
  let d = ''
  s.setEncoding('utf8')
  s.on('data', (c) => (d += c))
  s.on('end', () => res(d))
})

try {
  const raw = (await read(process.stdin)) || '{}'
  const dir = join(homedir(), '.claude', 'hooks')
  mkdirSync(dir, { recursive: true })
  appendFileSync(join(dir, 'subagent-notes.debug.log'), `\n=== ${new Date().toISOString()}\n${raw}\n`, 'utf8')
} catch (err) {
  console.error(`subagent-notes probe failed: ${err.message}`)
}
process.exit(0)
