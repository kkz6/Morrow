<script setup lang="ts">
import docs from '~/generated/docs.json'
const route = useRoute()
const page = computed(() => docs.find(item => item.slug === route.params.slug))
if (!page.value) throw createError({ statusCode: 404, statusMessage: 'Documentation page not found' })
const index = computed(() => docs.findIndex(item => item.slug === page.value?.slug))
const previous = computed(() => docs[index.value - 1])
const next = computed(() => docs[index.value + 1])
useSeoMeta({ title: () => `${page.value?.title} · Morrow Docs`, description: () => page.value?.description })
async function copyCode(event: MouseEvent) {
  const target = event.target as HTMLElement
  if (!target.matches('button[data-copy]')) return
  const text = target.parentElement?.querySelector('code')?.textContent || ''
  await navigator.clipboard.writeText(text)
  target.textContent = 'Copied'
  setTimeout(() => { target.textContent = 'Copy' }, 1600)
}
</script>

<template>
  <div v-if="page" class="article-layout">
    <article class="doc-article">
      <div class="eyebrow">{{ page.group.toUpperCase() }}</div><h1>{{ page.title }}</h1><p class="article-description">{{ page.description }}</p>
      <div class="prose" v-html="page.html" @click="copyCode"/>
      <a class="edit-link" :href="'https://github.com/kkz6/Morrow/edit/main/website/content/' + page.slug + '.md'">Edit this page on GitHub ↗</a>
      <nav class="article-pagination" aria-label="Adjacent pages"><NuxtLink v-if="previous" :to="'/docs/' + previous.slug"><span>← PREVIOUS</span><strong>{{ previous.title }}</strong></NuxtLink><NuxtLink v-if="next" :to="'/docs/' + next.slug"><span>NEXT →</span><strong>{{ next.title }}</strong></NuxtLink></nav>
    </article>
    <aside class="table-of-contents" v-if="page.headings.length"><h2>On this page</h2><a v-for="heading in page.headings" :key="heading.id" :href="'#' + heading.id" :class="{ nested: heading.depth === 3 }">{{ heading.title }}</a></aside>
  </div>
</template>
