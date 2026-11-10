import { readFile, access } from 'node:fs/promises'
const docs = JSON.parse(await readFile(new URL('../app/generated/docs.json', import.meta.url), 'utf8'))
const release = JSON.parse(await readFile(new URL('../app/generated/release.json', import.meta.url), 'utf8'))
const baseURL = (process.env.NUXT_APP_BASE_URL || '/').replace(/\/?$/, '/')
const slugs = new Set(docs.map(page => page.slug))
const failures = []
for (const page of docs) {
  if (!page.title || !page.description || !page.group || !Number.isFinite(page.order)) failures.push(`${page.slug}: incomplete metadata`)
  for (const [, href] of page.html.matchAll(/href="([^"#]+)(?:#[^"]*)?"/g)) {
    if (!href.startsWith('/') || href.startsWith('//')) continue
    if (!href.startsWith(`${baseURL}docs/`)) { failures.push(`${page.slug}: invalid local link ${href}`); continue }
    const slug = href.slice(`${baseURL}docs/`.length).replace(/\/$/, '')
    if (!slugs.has(slug)) failures.push(`${page.slug}: broken link ${href}`)
  }
  if (/\{\{(?:version|downloadUrl|releaseUrl)\}\}/.test(page.html)) failures.push(`${page.slug}: unresolved release placeholder`)
  try { await access(new URL(`../.output/public/docs/${page.slug}/index.html`, import.meta.url)) }
  catch { failures.push(`${page.slug}: missing prerendered output`) }
}
const gettingStarted = docs.find(page => page.slug === 'getting-started')
if (!gettingStarted?.html.includes(release.downloadUrl)) failures.push('Getting started is missing the published app download')
const homepage = await readFile(new URL('../.output/public/index.html', import.meta.url), 'utf8')
if (!homepage.includes(release.downloadUrl)) failures.push('Homepage is missing the published app download')
for (const asset of ['morrow-icon.png', 'morrow-workspace.png', 'workspace-pattern.png']) {
  try { await access(new URL(`../.output/public/images/${asset}`, import.meta.url)) }
  catch { failures.push(`Missing website asset: ${asset}`) }
}
const cli = await readFile(new URL('../../Sources/MorrowCLI/main.swift', import.meta.url), 'utf8')
const dbSwitch = cli.slice(cli.indexOf('switch subcommand {'), cli.indexOf('func printJSON'))
const commands = [...dbSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
const reference = docs.find(page => page.slug === 'cli-reference')?.text || ''
const mcpCommands = ['serve', 'status', 'enable', 'disable', 'access', 'config', 'add', 'remove']
for (const command of mcpCommands) if (!reference.includes(`morrow mcp ${command}`)) failures.push(`CLI reference is missing: morrow mcp ${command}`)
const binarySwitch = cli.slice(cli.indexOf('func binaryMain'), cli.indexOf('func toolsMain'))
const binaryCommands = [...binarySwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(binaryCommands)) if (!reference.includes(`morrow binary ${command}`)) failures.push(`CLI reference is missing: morrow binary ${command}`)
for (const command of ['status', 'clean', 'adopt', 'workers', 'restore']) if (!reference.includes(`morrow background ${command}`)) failures.push(`CLI reference is missing: morrow background ${command}`)
for (const command of new Set(commands)) if (!reference.includes(`morrow db ${command}`)) failures.push(`CLI reference is missing: morrow db ${command}`)
const toolSwitch = cli.slice(cli.indexOf('func toolsMain'), cli.indexOf('func projectMain'))
const toolCommands = [...toolSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(toolCommands)) if (!reference.includes(`morrow tool ${command}`)) failures.push(`CLI reference is missing: morrow tool ${command}`)
const projectSwitch = cli.slice(cli.indexOf('func projectMain'), cli.indexOf('func mailMain'))
const projectCommands = [...projectSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(projectCommands)) if (!reference.includes(`morrow project ${command}`)) failures.push(`CLI reference is missing: morrow project ${command}`)
const dumpsCommands = ['on', 'off', 'list', 'insights', 'clear']
for (const command of dumpsCommands) if (!reference.includes(`morrow dumps ${command}`)) failures.push(`CLI reference is missing: morrow dumps ${command}`)
const mailSwitch = cli.slice(cli.indexOf('func mailMain'), cli.indexOf('func siteMain'))
const mailCommands = [...mailSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(mailCommands)) if (!reference.includes(`morrow mail ${command}`)) failures.push(`CLI reference is missing: morrow mail ${command}`)
const siteSwitch = cli.slice(cli.indexOf('func siteMain'), cli.indexOf('func storageMain'))
const siteCommands = [...siteSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(siteCommands)) if (!reference.includes(`morrow site ${command}`)) failures.push(`CLI reference is missing: morrow site ${command}`)
const storageSwitch = cli.slice(cli.indexOf('func storageMain'), cli.indexOf('func syncMain'))
const storageCommands = [...storageSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(storageCommands)) if (!reference.includes(`morrow storage ${command}`)) failures.push(`CLI reference is missing: morrow storage ${command}`)
const syncSwitch = cli.slice(cli.indexOf('func syncMain'))
const syncCommands = [...syncSwitch.matchAll(/^    case ([^:]+):/gm)].flatMap(match => [...match[1].matchAll(/"([a-z-]+)"/g)].map(item => item[1]))
for (const command of new Set(syncCommands)) if (!reference.includes(`morrow sync ${command}`)) failures.push(`CLI reference is missing: morrow sync ${command}`)
try { await access(new URL('../.output/public/index.html', import.meta.url)) } catch { failures.push('Missing homepage') }
if (failures.length) { console.error(failures.join('\n')); process.exit(1) }
console.log(`Checked ${docs.length} prerendered docs pages, local documentation links, and ${new Set(commands).size + new Set(toolCommands).size + new Set(projectCommands).size + new Set(syncCommands).size + new Set(mailCommands).size + new Set(siteCommands).size + new Set(storageCommands).size + new Set(binaryCommands).size + dumpsCommands.length + mcpCommands.length + 2} CLI commands`)
