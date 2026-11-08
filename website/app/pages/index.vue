<script setup lang="ts">
import { PhArrowRight, PhArrowUpRight, PhCheck, PhCopy, PhDatabase, PhGlobe, PhCode, PhEnvelopeSimple, PhCube, PhTerminalWindow, PhPlus, PhMinus, PhShieldCheck, PhAppleLogo } from '@phosphor-icons/vue'
import release from '~/generated/release.json'
useSeoMeta({ title: 'Morrow — Your local stack, beautifully together', description: 'A native macOS workspace for databases, runtimes, local sites, mail, and S3. Download Morrow for Apple silicon. No Homebrew required.' })
const features = [
  { icon: PhDatabase, label: 'DATABASES', title: 'A database for every idea.', text: 'Choose an engine and version. Give it a name. Morrow handles the download, setup, and its own data directory.', chips: ['PostgreSQL', 'MySQL', 'Redis', '+4 more'], link: 'databases' },
  { icon: PhGlobe, label: 'LOCAL SITES', title: 'Your folder. Your domain.', text: 'Park your projects and visit folder-name.test. Add local HTTPS, link an app port, or choose which worktrees to host.', chips: ['Local DNS', 'HTTPS', 'Worktrees'], link: 'sites' },
  { icon: PhCode, label: 'RUNTIMES', title: 'The right version, right here.', text: 'PHP 8.4 for one project. Node 24 for another. Choose versions per folder, with the same choices in your terminal.', chips: ['PHP', 'Node.js', 'Go', 'Flutter'], link: 'project-versions' },
  { icon: PhEnvelopeSimple, label: 'MAIL', title: 'Emails with nowhere to go.', text: 'Catch messages from your app in a local inbox. Test sign-ins, receipts, and notifications without sending real mail.', chips: ['SMTP testing', 'Mailpit'], link: 'mail' },
  { icon: PhCube, label: 'OBJECT STORAGE', title: 'A bucket in your backyard.', text: 'Run an S3-compatible server on your Mac. Create buckets and test uploads with your app’s existing S3 client.', chips: ['MinIO', 'S3 compatible'], link: 'object-storage' },
  { icon: PhTerminalWindow, label: 'APP + CLI', title: 'Two ways. One workspace.', text: 'Click from your menu bar or type a command. Your instances, runtime choices, and settings stay in one place.', chips: ['Menu bar', 'morrow CLI'], link: 'cli-reference' }
]
const faqs = [
  { question: 'Is Morrow free?', answer: 'Yes. Morrow is free to download. Its source code is public on GitHub, where you can inspect the code, report issues, and contribute improvements.' },
  { question: 'What do I need to install first?', answer: 'Just Morrow. The signed app includes its CLI and downloads compatible services and runtimes when you need them. Homebrew and Xcode are not required to use it.' },
  { question: 'Which Macs are supported?', answer: 'Morrow supports Apple silicon Macs running macOS 14 or later. Some runtime distributions need a newer macOS version; Morrow filters out incompatible packages.' },
  { question: 'Will it change my existing projects?', answer: 'Morrow keeps your project files in place. It can reuse compatible software already installed on your Mac. Ignoring a site, excluding a worktree, or removing a parked directory removes local routes without deleting your folders.' },
  { question: 'How do app updates work?', answer: 'Open About → Check for Updates, or enable automatic update checks. Morrow verifies app updates before installing them. Database and runtime upgrades are separate actions that you control.' },
  { question: 'Is this for production servers?', answer: 'Morrow is a local development workspace. Services bind to your Mac, and local databases use development-friendly defaults. It is not a production hosting platform.' }
]
const command = 'morrow db create postgresql studio --start'
const copyState = ref('Copy command')
let copyTimer: ReturnType<typeof setTimeout> | undefined
async function copyCommand() {
  try { await navigator.clipboard.writeText(command); copyState.value = 'Copied' }
  catch { copyState.value = 'Select the command to copy' }
  clearTimeout(copyTimer); copyTimer = setTimeout(() => { copyState.value = 'Copy command' }, 2400)
}
onBeforeUnmount(() => clearTimeout(copyTimer))
</script>

<template>
  <div class="landing-page">
    <section class="hero" aria-labelledby="hero-title">
      <div class="hero-pattern" :style="{ backgroundImage: `url(${useSiteAsset('images/workspace-pattern.png')})` }" aria-hidden="true" />
      <div class="hero-content">
        <div class="eyebrow hero-eyebrow">A SMALL APP FOR BIG IDEAS</div>
        <h1 id="hero-title">Your local stack,<br><span>beautifully together.</span></h1>
        <p class="hero-description">Databases, runtimes, local sites, and the little things in between. One native Mac app to keep your development workspace running.</p>
        <div class="hero-actions"><DownloadButton /><NuxtLink class="button text-button" to="/docs/getting-started">Get to know Morrow <PhArrowRight :size="18" /></NuxtLink></div>
        <p class="compatibility"><span><PhAppleLogo :size="17" weight="fill" /> macOS 14+</span><span>Apple silicon</span><span>Free to download</span></p>
      </div>
      <figure class="hero-screenshot"><img :src="useSiteAsset('images/morrow-workspace.png')" alt="Morrow’s native Mac workspace showing PostgreSQL, MySQL, MongoDB, Redis, and Valkey instances with individual status and controls" width="1440" height="1240" fetchpriority="high"><figcaption>Your workspace, a click away. Actual Morrow interface with example projects.</figcaption></figure>
    </section>

    <section id="features" class="section-container features-section" aria-labelledby="features-title">
      <div class="section-heading"><div class="eyebrow">MAKE YOURSELF AT HOME</div><h2 id="features-title">Everything your project<br>calls home.</h2><p>Less tending to your tools. More time for what you’re building.</p></div>
      <div class="feature-grid"><NuxtLink v-for="feature in features" :key="feature.label" :to="'/docs/' + feature.link" class="feature-card"><div class="feature-top"><component :is="feature.icon" :size="28" weight="duotone" aria-hidden="true" /><span class="eyebrow">{{ feature.label }}</span><PhArrowUpRight :size="18" class="feature-arrow" /></div><h3>{{ feature.title }}</h3><p>{{ feature.text }}</p><div class="feature-chips"><span v-for="chip in feature.chips" :key="chip">{{ chip }}</span></div></NuxtLink></div>
    </section>

    <section class="workflow-section"><div class="section-container workflow-inner"><div class="workflow-copy"><div class="eyebrow">FROM DOWNLOAD TO DOING</div><h2>A fresh start.<br>Without the setup day.</h2><ol class="setup-steps"><li><span>01</span><div><h3>Make room for Morrow.</h3><p>Download the app and move it into Applications. The setup assistant helps you settle in.</p></div></li><li><span>02</span><div><h3>Bring your next project.</h3><p>Create a database, choose your runtimes, and add your project folder.</p></div></li><li><span>03</span><div><h3>Get back to building.</h3><p>Keep an eye on services from your menu bar, with logs and configuration close at hand.</p></div></li></ol><NuxtLink class="inline-link" to="/docs/getting-started">Read the getting started guide <PhArrowRight :size="18" /></NuxtLink></div>
      <div class="terminal-card"><div class="terminal-heading"><PhTerminalWindow :size="20" /><span>For the keyboard people.</span><button @click="copyCommand" :aria-label="copyState"><PhCheck v-if="copyState === 'Copied'" :size="19" /><PhCopy v-else :size="19" /></button></div><div class="terminal-content"><span class="terminal-comment"># Same workspace. Your way.</span><code><span>$</span> {{ command }}</code><p>Create an instance and start it<br>with a single command.</p><code><span>$</span> morrow site link --port 3000</code><p>Give your running app<br>a proper local address.</p><NuxtLink to="/docs/cli-reference">Explore the CLI <PhArrowUpRight :size="16" /></NuxtLink></div><span class="copy-status" role="status">{{ copyState === 'Copy command' ? '' : copyState }}</span></div>
    </div></section>

    <section id="install" class="section-container install-section"><div class="install-card"><BrandMark /><div class="eyebrow">VERSION {{ release.version }} · SIGNED & NOTARIZED</div><h2>Meet your new<br>local companion.</h2><p>Download. Open. Make something good.</p><DownloadButton /><div class="install-meta"><PhShieldCheck :size="18" /> Signed & notarized · macOS 14+ · Apple silicon</div><a :href="release.releaseUrl" class="release-link">Release notes and checksums <PhArrowUpRight :size="15" /></a></div></section>

    <section id="faq" class="section-container faq-section"><div><div class="eyebrow">A FEW GOOD QUESTIONS</div><h2>Before you<br>settle in.</h2><p>Something else on your mind?<br><a class="inline-link" href="https://github.com/kkz6/Morrow/issues">Ask us on GitHub <PhArrowUpRight :size="16" /></a></p></div><div class="faq-list"><details v-for="item in faqs" :key="item.question"><summary>{{ item.question }}<PhPlus class="faq-plus" :size="18" /><PhMinus class="faq-minus" :size="18" /></summary><p>{{ item.answer }}</p></details></div></section>
  </div>
</template>
