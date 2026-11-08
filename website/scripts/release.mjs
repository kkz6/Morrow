import { readFile } from 'node:fs/promises'

export async function publishedRelease() {
  const fallback = JSON.parse(await readFile(new URL('../release.json', import.meta.url), 'utf8'))
  try {
    const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'Morrow-Website' }
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`
    const response = await fetch('https://api.github.com/repos/kkz6/Morrow/releases/latest', { headers, signal: AbortSignal.timeout(10000) })
    if (!response.ok) throw new Error(`GitHub returned ${response.status}`)
    const release = await response.json()
    if (release.draft || release.prerelease || !/^v\d+\.\d+\.\d+$/.test(release.tag_name)) throw new Error('Not a stable published release')
    const version = release.tag_name.slice(1)
    const filename = `Morrow-${version}-macos-arm64.zip`
    const asset = release.assets.find(item => item.name === filename)
    const downloadUrl = `https://github.com/kkz6/Morrow/releases/download/v${version}/${filename}`
    const releaseUrl = `https://github.com/kkz6/Morrow/releases/tag/v${version}`
    if (!asset || asset.browser_download_url !== downloadUrl || release.html_url !== releaseUrl || asset.size <= 0) throw new Error('Missing release archive')
    return { version, downloadUrl, releaseUrl, size: asset.size }
  } catch (error) {
    console.warn(`Using verified release ${fallback.version}: ${error.message}`)
    return fallback
  }
}
