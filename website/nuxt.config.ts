import { readdirSync } from 'node:fs'

const documents = readdirSync(new URL('./content/', import.meta.url)).filter(file => file.endsWith('.md'))

export default defineNuxtConfig({
  compatibilityDate: '2026-10-07',
  devtools: { enabled: false },
  css: ['~/assets/main.css'],
  runtimeConfig: { public: { siteUrl: process.env.NUXT_PUBLIC_SITE_URL || 'https://kkz6.github.io/Morrow/' } },
  app: {
    baseURL: process.env.NUXT_APP_BASE_URL || '/',
    head: { htmlAttrs: { lang: 'en' }, title: 'Morrow — Your local development workspace', meta: [{ name: 'theme-color', content: '#f5f3ed' }, { name: 'description', content: 'A native Mac workspace for databases, runtimes, local sites, mail, and S3. Download Morrow for Apple silicon.' }] }
  },
  nitro: { preset: 'static', prerender: { crawlLinks: true, failOnError: true, routes: documents.map(file => '/docs/' + file.replace(/\.md$/, '')) } }
})
