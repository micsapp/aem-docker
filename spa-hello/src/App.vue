<script setup>
import { ref } from 'vue'

const message = ref('Hello World from Vue on AEM')
const count = ref(0)
</script>

<template>
  <main class="hello">
    <h1>{{ message }}</h1>
    <p>Served from AEM author at <code>/content/hello/</code></p>
    <button @click="count++">Clicked {{ count }} times</button>
  </main>
</template>

<style scoped>
.hello {
  font-family: system-ui, -apple-system, sans-serif;
  max-width: 640px;
  margin: 4rem auto;
  padding: 2rem;
  text-align: center;
}
h1 {
  color: #1f6feb;
  margin-bottom: 0.5rem;
}
button {
  margin-top: 1rem;
  padding: 0.5rem 1rem;
  font-size: 1rem;
  cursor: pointer;
}
</style>
