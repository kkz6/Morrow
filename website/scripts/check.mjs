import { readFile, access } from 'node:fs/promises'
const docs = JSON.parse(await readFile(new URL('../app/generated/docs.json', import.meta.url), 'utf8'))
const slugs = new Set(docs.map(page => page.slug))
const failures = []
for (const page of docs) {
  if (!page.title || !page.description || !page.group || !Number.isFinite(page.order)) failures.push(`${page.slug}: incomplete metadata`)
  for (const [, slug] of page.html.matchAll(/href="\/docs\/([^"#]+)(?:#[^"]+)?"/g)) if (!slugs.has(slug)) failures.push(`${page.slug}: broken link /docs/${slug}`)
  try { await access(new URL(`../.output/public/docs/${page.slug}/index.html`, import.meta.url)) }
  catch { failures.push(`${page.slug}: missing prerendered output`) }
}
const cli = await readFile(new URL('../../Sources/MorrowCLI/main.swift', import.meta.url), 'utf8')
const dbSwitch = cli.slice(cli.indexOf('switch subcommand {'), cli.indexOf('func printJSON'))
const commands = [...dbSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z]+)"/g)].map(item => item[1]))
const reference = docs.find(page => page.slug === 'cli-reference')?.text || ''
for (const command of new Set(commands)) if (!reference.includes(`morrow db ${command}`)) failures.push(`CLI reference is missing: morrow db ${command}`)
const toolSwitch = cli.slice(cli.indexOf('func toolsMain'), cli.indexOf('func mailMain'))
const toolCommands = [...toolSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z]+)"/g)].map(item => item[1]))
for (const command of new Set(toolCommands)) if (!reference.includes(`morrow tool ${command}`)) failures.push(`CLI reference is missing: morrow tool ${command}`)
const mailSwitch = cli.slice(cli.indexOf('func mailMain'), cli.indexOf('func syncMain'))
const mailCommands = [...mailSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z]+)"/g)].map(item => item[1]))
for (const command of new Set(mailCommands)) if (!reference.includes(`morrow mail ${command}`)) failures.push(`CLI reference is missing: morrow mail ${command}`)
const syncSwitch = cli.slice(cli.indexOf('func syncMain'))
const syncCommands = [...syncSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z]+)"/g)].map(item => item[1]))
for (const command of new Set(syncCommands)) if (!reference.includes(`morrow sync ${command}`)) failures.push(`CLI reference is missing: morrow sync ${command}`)
try { await access(new URL('../.output/public/index.html', import.meta.url)) } catch { failures.push('Missing homepage') }
if (failures.length) { console.error(failures.join('\n')); process.exit(1) }
console.log(`Checked ${docs.length} prerendered docs pages, local documentation links, and ${new Set(commands).size + new Set(toolCommands).size + new Set(syncCommands).size + new Set(mailCommands).size} CLI commands`)
