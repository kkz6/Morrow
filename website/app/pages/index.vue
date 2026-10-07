<script setup lang="ts">
useSeoMeta({ title: 'Morrow — Native databases, one workspace', description: 'Documentation for Morrow, a native macOS menu bar app and CLI for local databases.' })
const command = 'morrow db create postgresql my-app --start'
const copied = ref(false)
async function copyCommand() { await navigator.clipboard.writeText(command); copied.value = true; setTimeout(() => { copied.value = false }, 1800) }
</script>

<template>
  <div class="welcome-page">
    <div class="eyebrow"><span class="status-dot"/> MACOS APP + CLI</div>
    <h1>Your databases.<br><span>A little closer.</span></h1>
    <p class="hero-description">Create a local database from your menu bar or terminal. Choose a version, name your instance, and get back to building.</p>
    <div class="hero-actions"><NuxtLink class="button primary" to="/docs/getting-started">Get started <span aria-hidden="true">→</span></NuxtLink><NuxtLink class="button secondary" to="/docs/cli-reference">Explore the CLI</NuxtLink></div>
    <div class="terminal-example">
      <div class="terminal-header"><span class="terminal-dots"><i/><i/><i/></span><span>YOUR FIRST DATABASE</span><button @click="copyCommand">{{ copied ? 'Copied' : 'Copy' }}</button></div>
      <div class="terminal-body"><code><span class="prompt">$</span> {{ command }}</code><p>One command. A database of its own.</p><span class="terminal-note"><span class="status-dot"/> Existing binaries are reused. Missing versions are handled automatically.</span></div>
    </div>
    <section class="guide-section"><div class="section-top"><h2>A good place to start</h2><span>FROM SETUP TO EVERYDAY USE</span></div>
      <div class="guide-grid">
        <NuxtLink to="/docs/getting-started" class="guide-card"><span class="guide-number">01</span><h3>Your first instance <span>↗</span></h3><p>Build Morrow, open the app, and create your workspace.</p></NuxtLink>
        <NuxtLink to="/docs/databases" class="guide-card"><span class="guide-number">02</span><h3>Choose a database <span>↗</span></h3><p>PostgreSQL, MySQL, MongoDB, Redis, and more.</p></NuxtLink>
        <NuxtLink to="/docs/cli-reference" class="guide-card"><span class="guide-number">03</span><h3>Work in Terminal <span>↗</span></h3><p>The same instances and settings, through the morrow command.</p></NuxtLink>
        <NuxtLink to="/docs/logs-and-storage" class="guide-card"><span class="guide-number">04</span><h3>See what’s happening <span>↗</span></h3><p>Follow logs, find data, and understand the service lifecycle.</p></NuxtLink>
      </div>
    </section>
    <div class="engine-strip"><span>BUILT FOR LOCAL DEVELOPMENT</span><p>PostgreSQL <b>·</b> MySQL <b>·</b> MariaDB <b>·</b> MongoDB <b>·</b> Redis <b>·</b> Valkey <b>·</b> Memcached</p></div>
    <footer class="page-footer"><BrandMark /><span>A small app for the work you do every day.</span><a href="https://github.com/kkz6/Morrow">View the source ↗</a></footer>
  </div>
</template>
