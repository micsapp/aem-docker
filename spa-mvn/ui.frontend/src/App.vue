<script setup>
import { ref, onMounted } from 'vue'
import { fetchAll } from './lib/aem.js'

import AppHeader from './components/AppHeader.vue'
import HeroSection from './components/HeroSection.vue'
import FeatureGrid from './components/FeatureGrid.vue'
import StatsBar from './components/StatsBar.vue'
import LogoStrip from './components/LogoStrip.vue'
import CTABanner from './components/CTABanner.vue'
import AppFooter from './components/AppFooter.vue'

const loading = ref(true)
const error = ref(null)
const hero = ref({})
const features = ref([])
const stats = ref([])
const ctaBanner = ref({})

onMounted(async () => {
  try {
    const data = await fetchAll()
    hero.value = data.hero
    features.value = data.features
    stats.value = data.stats
    ctaBanner.value = data.ctaBanner
  } catch (err) {
    console.error('[spa-mvn] failed to load Content Fragments:', err)
    error.value = err.message || String(err)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <AppHeader />

  <div v-if="loading" class="loader">
    <div class="loader__pulse"></div>
    <p class="loader__label">Loading content&hellip;</p>
  </div>

  <div v-else-if="error" class="loader loader--error">
    <p class="loader__label">Couldn&rsquo;t load page content.</p>
    <pre class="loader__detail">{{ error }}</pre>
    <p class="loader__hint">
      Check that the AEM author/publish is reachable and that the Content Fragments at
      <code>/content/dam/spa-mvn/cf/</code> exist and are anon-readable.
    </p>
  </div>

  <main v-else>
    <HeroSection :hero="hero" />
    <LogoStrip />
    <FeatureGrid :items="features" />
    <StatsBar :stats="stats" />
    <CTABanner :cta="ctaBanner" />
  </main>

  <AppFooter />
</template>

<style scoped>
.loader {
  min-height: 60vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 80px 24px;
  text-align: center;
}
.loader__pulse {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: linear-gradient(135deg, #1473e6, #ff3b30);
  margin-bottom: 18px;
  animation: pulse 1.4s ease-in-out infinite;
}
.loader__label { font-size: 15px; color: #666; margin: 0; }
.loader__detail {
  margin-top: 14px;
  padding: 12px 18px;
  background: #fff4f3;
  border: 1px solid #ffd6d2;
  border-radius: 8px;
  font-size: 13px;
  color: #a02020;
  max-width: 540px;
  overflow: auto;
}
.loader__hint { font-size: 13px; color: #888; margin-top: 14px; max-width: 540px; }
.loader__hint code { background: #f3f3f3; padding: 2px 6px; border-radius: 4px; font-size: 12px; }

@keyframes pulse {
  0%, 100% { transform: scale(0.85); opacity: 0.6; }
  50%      { transform: scale(1.0);  opacity: 1.0; }
}
</style>
