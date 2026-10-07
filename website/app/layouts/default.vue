<script setup lang="ts">
import docs from '~/generated/docs.json'
const route = useRoute()
const search = ref('')
const dialog = ref<HTMLDialogElement>()
const searchField = ref<HTMLInputElement>()
const menuOpen = ref(false)
const groups = computed(() => [...new Set(docs.map(page => page.group))])
const results = computed(() => {
  const query = search.value.toLowerCase().trim()
  return query ? docs.filter(page => (page.title + ' ' + page.text).toLowerCase().includes(query)) : docs.slice(0, 6)
})
function openSearch() { dialog.value?.showModal(); nextTick(() => searchField.value?.focus()) }
function closeSearch() { dialog.value?.close(); search.value = '' }
function shortcut(event: KeyboardEvent) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') { event.preventDefault(); openSearch() }
}
watch(() => route.fullPath, () => { closeSearch(); menuOpen.value = false })
onMounted(() => window.addEventListener('keydown', shortcut))
onBeforeUnmount(() => window.removeEventListener('keydown', shortcut))
</script>

<template>
  <header class="site-header">
    <NuxtLink class="brand" to="/"><BrandMark /><strong>Morrow</strong><span class="brand-divider"/><span class="brand-label">Documentation</span></NuxtLink>
    <div class="header-actions">
      <button class="search-trigger" @click="openSearch"><span aria-hidden="true">⌕</span> Search documentation <kbd>⌘ K</kbd></button>
      <a class="github-link" href="https://github.com/kkz6/Morrow" target="_blank" rel="noopener">GitHub <span aria-hidden="true">↗</span></a>
      <button class="mobile-menu" aria-label="Toggle navigation" :aria-expanded="menuOpen" @click="menuOpen = !menuOpen">☰</button>
    </div>
  </header>
  <div class="docs-shell">
    <aside class="sidebar" :class="{ open: menuOpen }">
      <NuxtLink to="/" class="sidebar-home" :class="{ active: route.path === '/' }"><span aria-hidden="true">◈</span> Welcome to Morrow</NuxtLink>
      <section v-for="group in groups" :key="group" class="nav-group">
        <h2>{{ group }}</h2>
        <NuxtLink v-for="page in docs.filter(item => item.group === group)" :key="page.slug" :to="'/docs/' + page.slug" :class="{ active: route.path === '/docs/' + page.slug }">{{ page.title }}</NuxtLink>
      </section>
      <div class="sidebar-note"><span class="status-dot"/> v0.1 · Developer preview<p>Native tools. One workspace.</p></div>
    </aside>
    <main id="main-content"><slot /></main>
  </div>
  <dialog ref="dialog" class="search-dialog" @click="event => { if (event.target === dialog) closeSearch() }">
    <div class="search-box"><span aria-hidden="true">⌕</span><input ref="searchField" v-model="search" placeholder="Search commands, guides, and features…" aria-label="Search documentation"><button @click="closeSearch" aria-label="Close search"><kbd>esc</kbd></button></div>
    <div class="search-results">
      <NuxtLink v-for="page in results" :key="page.slug" :to="'/docs/' + page.slug"><span class="result-group">{{ page.group }}</span><strong>{{ page.title }}</strong><span>{{ page.description }}</span><span class="result-arrow" aria-hidden="true">↗</span></NuxtLink>
      <p v-if="results.length === 0" class="no-results">No matching pages. Try an engine name or command.</p>
    </div>
  </dialog>
</template>
