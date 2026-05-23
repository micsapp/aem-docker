<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  cta: {
    type: Object,
    default: () => ({ title: '', lede: '', ctaLabel: 'Submit' })
  }
})

const email = ref('')
const submitted = ref(false)
const buttonLabel = computed(() =>
  submitted.value ? "Thanks — we'll be in touch" : (props.cta.ctaLabel || 'Submit')
)

function submit() {
  if (!email.value) return
  submitted.value = true
}
</script>

<template>
  <section class="cta section--gray">
    <div class="container">
      <div class="cta__card">
        <div>
          <h2 class="cta__title">{{ cta.title }}</h2>
          <p class="cta__lede">{{ cta.lede }}</p>
        </div>

        <form class="cta__form" @submit.prevent="submit">
          <input
            v-model="email"
            type="email"
            placeholder="Work email"
            required
            class="cta__input"
            :disabled="submitted"
          />
          <button type="submit" class="cta__btn" :disabled="submitted">{{ buttonLabel }}</button>
        </form>
      </div>
    </div>
  </section>
</template>

<style scoped>
.cta { padding: 80px 0; }
.cta__card {
  background: linear-gradient(135deg, #1473e6 0%, #6a2bff 100%);
  color: #ffffff;
  border-radius: 24px;
  padding: 56px;
  display: grid;
  grid-template-columns: 1.4fr 1fr;
  gap: 32px;
  align-items: center;
}
@media (max-width: 880px) { .cta__card { grid-template-columns: 1fr; padding: 40px 28px; } }

.cta__title {
  font-size: clamp(24px, 2.6vw, 34px);
  font-weight: 800;
  letter-spacing: -0.02em;
  margin: 0 0 12px;
}
.cta__lede { margin: 0; opacity: 0.88; font-size: 16px; }

.cta__form { display: flex; gap: 10px; }
.cta__input {
  flex: 1;
  padding: 14px 18px;
  border-radius: 999px;
  border: none;
  font-size: 15px;
  outline: 2px solid transparent;
  transition: outline-color 0.15s ease;
  background: rgba(255, 255, 255, 0.96);
  color: #1a1a1a;
}
.cta__input:focus { outline-color: rgba(255, 255, 255, 0.8); }
.cta__input:disabled { opacity: 0.65; }

.cta__btn {
  padding: 14px 22px;
  border-radius: 999px;
  border: none;
  background: #1a1a1a;
  color: white;
  font-weight: 600;
  font-size: 15px;
  transition: background 0.15s ease;
  white-space: nowrap;
}
.cta__btn:hover:not(:disabled) { background: #000000; }
.cta__btn:disabled { background: rgba(0, 0, 0, 0.5); cursor: default; }
</style>
