<script setup lang="ts">
import { PhGithubLogo, PhMagnifyingGlass, PhList, PhX, PhHouse, PhArrowUpRight } from '@phosphor-icons/vue'
import docs from '~/generated/docs.json'
import release from '~/generated/release.json'
const route = useRoute()
const isDocs = computed(() => route.path.startsWith('/docs/'))
const search = ref('')
const dialog = ref<HTMLDialogElement>()
const searchField = ref<HTMLInputElement>()
const menuOpen = ref(false)
const groups = computed(() => [...new Set(docs.map(page => page.group))])
const results = computed(() => {
  const query = search.value.toLowerCase().trim()
  return query ? docs.filter(page => (page.title + ' ' + page.text).toLowerCase().includes(query)) : docs.slice(0, 6)
})
function openSearch() { menuOpen.value = false; dialog.value?.showModal(); nextTick(() => searchField.value?.focus()) }
function closeSearch() { dialog.value?.close(); search.value = '' }
function shortcut(event: KeyboardEvent) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') { event.preventDefault(); openSearch() }
  if (event.key === 'Escape') menuOpen.value = false
}
watch(() => route.fullPath, () => { closeSearch(); menuOpen.value = false })
onMounted(() => window.addEventListener('keydown', shortcut))
onBeforeUnmount(() => window.removeEventListener('keydown', shortcut))
</script>

<template>
  <a class="skip-link" href="#main-content">Skip to content</a>
  <header class="site-header">
    <div class="header-inner">
      <NuxtLink class="brand" to="/" aria-label="Morrow home"><BrandMark /><strong>Morrow</strong><span class="version-label">v{{ release.version }}</span></NuxtLink>
      <nav class="primary-nav" aria-label="Main navigation"><NuxtLink to="/#features">Features</NuxtLink><NuxtLink to="/docs/getting-started" :class="{ selected: isDocs }">Documentation</NuxtLink><a :href="release.releaseUrl">Changelog</a><NuxtLink to="/#faq">FAQ</NuxtLink></nav>
      <div class="header-actions">
        <button v-if="isDocs" class="icon-button search-trigger" aria-label="Search documentation" @click="openSearch"><PhMagnifyingGlass :size="20" /></button>
        <a class="icon-button github-link" href="https://github.com/kkz6/Morrow" aria-label="Morrow on GitHub"><PhGithubLogo :size="21" /></a>
        <DownloadButton small />
        <button class="icon-button mobile-menu" aria-label="Toggle navigation" :aria-expanded="menuOpen" aria-controls="mobile-navigation" @click="menuOpen = !menuOpen"><PhX v-if="menuOpen" :size="23" /><PhList v-else :size="23" /></button>
      </div>
    </div>
    <nav v-if="menuOpen" id="mobile-navigation" class="mobile-navigation" aria-label="Mobile navigation">
      <NuxtLink to="/#features">Features</NuxtLink><NuxtLink to="/docs/getting-started">Documentation</NuxtLink><a :href="release.releaseUrl">Changelog</a><NuxtLink to="/#faq">FAQ</NuxtLink>
      <button @click="openSearch"><PhMagnifyingGlass :size="18" /> Search documentation</button>
      <template v-if="isDocs"><section v-for="group in groups" :key="group"><h2>{{ group }}</h2><NuxtLink v-for="page in docs.filter(item => item.group === group)" :key="page.slug" :to="'/docs/' + page.slug">{{ page.title }}</NuxtLink></section></template>
    </nav>
  </header>
  <div v-if="isDocs" class="docs-shell">
    <aside class="sidebar" aria-label="Documentation navigation">
      <button class="sidebar-search" @click="openSearch"><PhMagnifyingGlass :size="17" /><span>Find a guide…</span><kbd>⌘ K</kbd></button>
      <NuxtLink to="/" class="sidebar-home"><PhHouse :size="17" /> Back to Morrow</NuxtLink>
      <section v-for="group in groups" :key="group" class="nav-group"><h2>{{ group }}</h2><NuxtLink v-for="page in docs.filter(item => item.group === group)" :key="page.slug" :to="'/docs/' + page.slug" :class="{ active: route.path === '/docs/' + page.slug }" :aria-current="route.path === '/docs/' + page.slug ? 'page' : undefined">{{ page.title }}</NuxtLink></section>
      <div class="sidebar-download"><BrandMark /><strong>Your workspace awaits.</strong><p>macOS 14+ · Apple silicon</p><a :href="release.downloadUrl">Download v{{ release.version }} <PhArrowUpRight :size="16" /></a></div>
    </aside>
    <main id="main-content" tabindex="-1"><slot /></main>
  </div>
  <main v-else id="main-content" tabindex="-1"><slot /></main>
  <SiteFooter />
  <dialog ref="dialog" class="search-dialog" aria-label="Search documentation" @click="event => { if (event.target === dialog) closeSearch() }" @close="search = ''">
    <div class="search-box"><PhMagnifyingGlass :size="22" /><input ref="searchField" v-model="search" placeholder="Search guides, commands, and features…" aria-label="Search documentation"><button class="icon-button" @click="closeSearch" aria-label="Close search"><PhX :size="20" /></button></div>
    <div class="search-results"><NuxtLink v-for="page in results" :key="page.slug" :to="'/docs/' + page.slug"><span class="result-group">{{ page.group }}</span><strong>{{ page.title }}</strong><span>{{ page.description }}</span><PhArrowUpRight class="result-arrow" :size="19" /></NuxtLink><p v-if="results.length === 0" class="no-results">No matching guides. Try “PHP”, “sites”, or a command.</p></div>
    <div class="search-hint">Search all {{ docs.length }} guides <kbd>esc to close</kbd></div>
  </dialog>
</template>
