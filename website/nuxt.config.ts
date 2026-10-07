import { readdirSync } from 'node:fs'

const documents = readdirSync(new URL('./content/', import.meta.url)).filter(file => file.endsWith('.md'))

export default defineNuxtConfig({
  compatibilityDate: '2026-10-07',
  devtools: { enabled: false },
  css: ['~/assets/main.css'],
  app: {
    baseURL: process.env.NUXT_APP_BASE_URL || '/',
    head: { title: 'Morrow Docs', meta: [{ name: 'description', content: 'A native macOS database manager and CLI. Create databases, choose versions, and manage local development from your menu bar or terminal.' }] }
  },
  nitro: { preset: 'static', prerender: { crawlLinks: true, failOnError: true, routes: documents.map(file => '/docs/' + file.replace(/\.md$/, '')) } }
})
