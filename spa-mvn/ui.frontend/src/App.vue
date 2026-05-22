<script setup>
import AppHeader from './components/AppHeader.vue'
import HeroSection from './components/HeroSection.vue'
import FeatureGrid from './components/FeatureGrid.vue'
import StatsBar from './components/StatsBar.vue'
import LogoStrip from './components/LogoStrip.vue'
import CTABanner from './components/CTABanner.vue'
import AppFooter from './components/AppFooter.vue'
</script>

<template>
  <AppHeader />
  <main>
    <HeroSection />
    <LogoStrip />
    <FeatureGrid />
    <StatsBar />
    <CTABanner />
  </main>
  <AppFooter />
</template>
