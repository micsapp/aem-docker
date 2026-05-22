<script setup>
defineProps({
  icon: { type: String, required: true },
  title: { type: String, required: true },
  body: { type: String, required: true }
})
</script>

<template>
  <article class="card">
    <div class="card__icon" v-html="icon"></div>
    <h3 class="card__title">{{ title }}</h3>
    <p class="card__body">{{ body }}</p>
    <a href="#" class="card__link">Learn more &rarr;</a>
  </article>
</template>

<style scoped>
.card {
  background: #ffffff;
  border: 1px solid #ececec;
  border-radius: 16px;
  padding: 32px;
  transition: border-color 0.2s ease, transform 0.2s ease, box-shadow 0.2s ease;
}
.card:hover {
  border-color: #1473e6;
  transform: translateY(-3px);
  box-shadow: 0 12px 30px -10px rgba(20, 115, 230, 0.2);
}
.card__icon {
  display: inline-grid;
  place-items: center;
  width: 48px;
  height: 48px;
  border-radius: 12px;
  background: linear-gradient(135deg, #eaf2ff, #ffe6e4);
  color: #1473e6;
  margin-bottom: 18px;
}
.card__icon :deep(svg) { width: 24px; height: 24px; }

.card__title {
  font-size: 18px;
  font-weight: 700;
  margin: 0 0 10px;
  letter-spacing: -0.01em;
}
.card__body {
  font-size: 15px;
  color: #555;
  margin: 0 0 18px;
}
.card__link {
  font-size: 14px;
  font-weight: 600;
  color: #1473e6;
}
.card__link:hover { text-decoration: underline; }
</style>
