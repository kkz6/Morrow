import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises'
import { marked } from 'marked'

const directory = new URL('../content/', import.meta.url)
const entries = []
for (const filename of (await readdir(directory)).filter(file => file.endsWith('.md'))) {
  const source = await readFile(new URL(filename, directory), 'utf8')
  const [, frontmatter, body] = source.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/) || []
  if (!frontmatter) throw new Error(`Missing metadata: ${filename}`)
  const meta = Object.fromEntries(frontmatter.split('\n').filter(Boolean).map(line => {
    const split = line.indexOf(':')
    return [line.slice(0, split).trim(), line.slice(split + 1).trim()]
  }))
  const headings = []
  const used = new Map()
  const html = marked.parse(body).replace(/<pre>/g, '<pre><button data-copy aria-label="Copy code">Copy</button>').replace(/<h([1-6])>([\s\S]*?)<\/h\1>/g, (_, depth, text) => {
    const title = text.replace(/<[^>]*>/g, '')
    const base = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
    const count = used.get(base) || 0
    used.set(base, count + 1)
    const id = count ? `${base}-${count}` : base
    if (Number(depth) > 1 && Number(depth) < 4) headings.push({ id, title, depth: Number(depth) })
    return `<h${depth} id="${id}">${text}</h${depth}>`
  })
  entries.push({ slug: filename.replace(/\.md$/, ''), title: meta.title, description: meta.description,
    group: meta.group, order: Number(meta.order), html, headings, text: body.replace(/[#`*]/g, '') })
}
entries.sort((a, b) => a.order - b.order)
const output = new URL('../app/generated/', import.meta.url)
await mkdir(output, { recursive: true })
await writeFile(new URL('docs.json', output), JSON.stringify(entries, null, 2))
console.log(`Built ${entries.length} documentation pages from Markdown`)
