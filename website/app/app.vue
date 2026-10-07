<script setup lang="ts">
const config = useRuntimeConfig()
useHead({ link: [{ rel: 'icon', type: 'image/svg+xml', href: config.app.baseURL + 'favicon.svg' }] })
</script>

<template>
  <NuxtLayout><NuxtPage /></NuxtLayout>
</template>
