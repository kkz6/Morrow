<script setup lang="ts">
import { PhArrowUpRight } from '@phosphor-icons/vue'
import release from '~/generated/release.json'
</script>
<template>
  <footer class="site-footer">
    <div class="footer-inner">
      <div class="footer-intro">
        <NuxtLink class="brand" to="/"><BrandMark /><strong>Morrow</strong></NuxtLink>
        <p>A little less setup.<br>A little more building.</p>
        <span class="footer-credit">Made for the work you love. © {{ new Date().getFullYear() }} Morrow.</span>
      </div>
      <div><h2>Product</h2><NuxtLink to="/#features">Features</NuxtLink><NuxtLink to="/#install">Download</NuxtLink><a :href="release.releaseUrl">Release notes <PhArrowUpRight :size="13" /></a><NuxtLink to="/#faq">Questions & answers</NuxtLink></div>
      <div><h2>Learn</h2><NuxtLink to="/docs/getting-started">Getting started</NuxtLink><NuxtLink to="/docs/sites">Local sites</NuxtLink><NuxtLink to="/docs/cli-reference">CLI reference</NuxtLink><NuxtLink to="/docs/contributing">Contributing</NuxtLink></div>
      <div><h2>Elsewhere</h2><a href="https://github.com/kkz6/Morrow">GitHub <PhArrowUpRight :size="13" /></a><a href="https://github.com/kkz6/Morrow/issues">Feedback <PhArrowUpRight :size="13" /></a><a href="https://zonebar.karti.dev/">ZoneBar <PhArrowUpRight :size="13" /></a><a href="https://karti.dev/">Made by Karthick <PhArrowUpRight :size="13" /></a></div>
    </div>
  </footer>
</template>
