<script setup lang="ts">
const config = useRuntimeConfig()
const route = useRoute()
const canonical = computed(() => new URL(route.path.replace(/^\//, ''), config.public.siteUrl).href)
useHead(() => ({ link: [{ rel: 'icon', type: 'image/png', href: config.app.baseURL + 'images/morrow-icon.png' }, { rel: 'canonical', href: canonical.value }] }))
useSeoMeta({ ogSiteName: 'Morrow', ogType: 'website', ogUrl: () => canonical.value, ogImage: new URL('images/morrow-workspace.png', config.public.siteUrl).href, twitterCard: 'summary_large_image' })
</script>

<template>
  <NuxtLayout><NuxtPage /></NuxtLayout>
</template>
