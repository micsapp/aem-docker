<script setup>
import FeatureCard from './FeatureCard.vue'

defineProps({
  items: {
    type: Array,
    default: () => []
  }
})

// Map from iconKey (string stored in CF) to inline SVG used for rendering.
const icons = {
  editor: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M9 21V9"/></svg>`,
  code:   `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>`,
  target: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="4"/></svg>`,
  check:  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>`,
  photo:  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="M21 15l-5-5L5 21"/></svg>`,
  globe:  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`
}
function iconFor(key) { return icons[key] || icons.editor }
</script>

<template>
  <section class="features section">
    <div class="container">
      <header class="features__head">
        <p class="features__eyebrow">Platform</p>
        <h2 class="features__title">Everything your team needs to ship faster</h2>
        <p class="features__lede">
          One platform for authoring, delivery, and measurement &mdash; so you stop stitching tools and
          start shipping.
        </p>
      </header>

      <div class="features__grid">
        <FeatureCard
          v-for="f in items"
          :key="f.title"
          :icon="iconFor(f.iconKey)"
          :title="f.title"
          :body="f.body"
        />
      </div>
    </div>
  </section>
</template>

<style scoped>
.features__head { max-width: 720px; margin: 0 auto 56px; text-align: center; }
.features__eyebrow {
  font-size: 13px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: #1473e6;
  margin: 0 0 14px;
}
.features__title {
  font-size: clamp(28px, 3.5vw, 42px);
  font-weight: 800;
  line-height: 1.15;
  letter-spacing: -0.02em;
  margin: 0 0 18px;
}
.features__lede {
  font-size: 17px;
  color: #555;
  margin: 0;
}
.features__grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 24px;
}
@media (max-width: 980px) { .features__grid { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 640px) { .features__grid { grid-template-columns: 1fr; } }
</style>
