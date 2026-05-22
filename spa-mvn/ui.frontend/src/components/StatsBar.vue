<script setup>
const stats = [
  { value: '12,000+', label: 'Brands shipping daily' },
  { value: '4.2B', label: 'Page renders / month' },
  { value: '99.99%', label: 'Platform uptime SLA' },
  { value: '38ms', label: 'Median edge latency' }
]
</script>

<template>
  <section class="stats section--tight section--dark">
    <div class="container">
      <div class="stats__grid">
        <div v-for="s in stats" :key="s.label" class="stats__item">
          <div class="stats__value">{{ s.value }}</div>
          <div class="stats__label">{{ s.label }}</div>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.stats__grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 24px;
}
@media (max-width: 760px) { .stats__grid { grid-template-columns: repeat(2, 1fr); } }

.stats__item { text-align: center; }
.stats__value {
  font-size: clamp(32px, 4vw, 48px);
  font-weight: 800;
  letter-spacing: -0.03em;
  background: linear-gradient(135deg, #ffffff, #b5c3ff);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  margin-bottom: 6px;
}
.stats__label {
  font-size: 14px;
  color: rgba(255, 255, 255, 0.7);
  letter-spacing: 0.02em;
}
</style>
