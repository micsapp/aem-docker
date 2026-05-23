<script setup>
import EditableText from './EditableText.vue'

defineProps({
  stats: {
    type: Array,
    default: () => []
  }
})
</script>

<template>
  <section class="stats section--tight section--dark">
    <div class="container">
      <div class="stats__grid">
        <div v-for="s in stats" :key="s._path || s.label" class="stats__item">
          <EditableText tag="div" class="stats__value" :fragment-path="s._path" field-name="value" :model-value="s.value" />
          <EditableText tag="div" class="stats__label" :fragment-path="s._path" field-name="label" :model-value="s.label" />
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
