<script setup>
const logos = ['NEXORA', 'ORBITAL', 'METRICA', 'KAIROS', 'LUMENS', 'VERTEX']
</script>

<template>
  <section class="logos">
    <div class="container">
      <p class="logos__label">Trusted by content teams at</p>
      <div class="logos__row">
        <span v-for="name in logos" :key="name" class="logos__item">{{ name }}</span>
      </div>
    </div>
  </section>
</template>

<style scoped>
.logos {
  padding: 56px 0;
  background: #ffffff;
  border-bottom: 1px solid #f0f0f0;
}
.logos__label {
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: #888;
  text-align: center;
  margin: 0 0 28px;
}
.logos__row {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-around;
  align-items: center;
  gap: 32px;
}
.logos__item {
  font-size: 22px;
  font-weight: 800;
  letter-spacing: 0.15em;
  color: #b5b5b5;
  transition: color 0.2s ease;
}
.logos__item:hover { color: #1a1a1a; }
</style>
