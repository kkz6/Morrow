<script setup lang="ts">
import { PhDownloadSimple } from '@phosphor-icons/vue'
import release from '~/generated/release.json'
defineProps<{ small?: boolean }>()
</script>

<template>
  <a :href="release.downloadUrl" class="button download-button" :class="{ small }" :aria-label="`Download Morrow ${release.version} for macOS, Apple silicon`">
    <PhDownloadSimple :size="small ? 17 : 20" aria-hidden="true" />
    <span>{{ small ? 'Download' : 'Download for macOS' }}</span>
  </a>
</template>
