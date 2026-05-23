<script setup>
import { computed } from 'vue'
import { editMode } from '../lib/edit.js'
import EditableText from './EditableText.vue'

const props = defineProps({
  hero: {
    type: Object,
    default: () => ({
      _path: 'hero',
      eyebrow: '', title: 'Loading…', accent: '', lede: '',
      ctaPrimaryLabel: '', ctaPrimaryUrl: '#',
      ctaSecondaryLabel: '', ctaSecondaryUrl: '#'
    })
  }
})
const path = computed(() => props.hero._path || 'hero')
</script>

<template>
  <section class="hero">
    <div class="hero__bg"></div>
    <div class="container hero__inner">
      <EditableText
        v-if="hero.eyebrow || editMode"
        tag="p" class="hero__eyebrow"
        :fragment-path="path" field-name="eyebrow"
        :model-value="hero.eyebrow"
      />
      <h1 class="hero__title">
        <EditableText tag="span" :fragment-path="path" field-name="title" :model-value="hero.title" />
        <EditableText
          v-if="hero.accent || editMode"
          tag="span" class="hero__accent"
          :fragment-path="path" field-name="accent"
          :model-value="hero.accent"
        />.
      </h1>
      <EditableText
        v-if="hero.lede || editMode"
        tag="p" class="hero__lede"
        :fragment-path="path" field-name="lede"
        :model-value="hero.lede"
      />
      <div class="hero__actions">
        <a v-if="hero.ctaPrimaryLabel || editMode" :href="hero.ctaPrimaryUrl || '#'" class="btn btn--primary">
          <EditableText tag="span" :fragment-path="path" field-name="ctaPrimaryLabel" :model-value="hero.ctaPrimaryLabel" />
        </a>
        <a v-if="hero.ctaSecondaryLabel || editMode" :href="hero.ctaSecondaryUrl || '#'" class="btn btn--ghost">
          <span class="btn__play">&#9658;</span>
          <EditableText tag="span" :fragment-path="path" field-name="ctaSecondaryLabel" :model-value="hero.ctaSecondaryLabel" />
        </a>
      </div>
      <div class="hero__meta">
        <span class="hero__meta-item">★ 4.7 G2 rating</span>
        <span class="hero__meta-dot">·</span>
        <span class="hero__meta-item">SOC 2 Type II</span>
        <span class="hero__meta-dot">·</span>
        <span class="hero__meta-item">No credit card required</span>
      </div>
    </div>
  </section>
</template>

<style scoped>
.hero {
  position: relative;
  overflow: hidden;
  padding: 120px 0 96px;
  color: #ffffff;
}

.hero__bg {
  position: absolute;
  inset: 0;
  background:
    radial-gradient(1200px 600px at 20% -10%, rgba(20, 115, 230, 0.55), transparent 60%),
    radial-gradient(900px 500px at 90% 10%, rgba(255, 59, 48, 0.45), transparent 60%),
    linear-gradient(180deg, #0c0e2c 0%, #14163a 100%);
  z-index: -1;
}

.hero__inner { position: relative; max-width: 980px; }

.hero__eyebrow {
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.7);
  margin: 0 0 20px;
}

.hero__title {
  font-size: clamp(40px, 6vw, 68px);
  font-weight: 800;
  line-height: 1.05;
  letter-spacing: -0.02em;
  margin: 0 0 24px;
}
.hero__accent {
  background: linear-gradient(135deg, #ff3b30, #ffb86b);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.hero__lede {
  font-size: clamp(17px, 1.5vw, 20px);
  line-height: 1.55;
  color: rgba(255, 255, 255, 0.82);
  max-width: 680px;
  margin: 0 0 36px;
}

.hero__actions { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 28px; }

.btn {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 14px 24px;
  border-radius: 999px;
  font-size: 15px;
  font-weight: 600;
  border: none;
  transition: transform 0.15s ease, background 0.15s ease;
}
.btn--primary { background: #ffffff; color: #0c0e2c; }
.btn--primary:hover { background: #f0f0f0; transform: translateY(-1px); }

.btn--ghost {
  background: rgba(255, 255, 255, 0.08);
  color: white;
  border: 1px solid rgba(255, 255, 255, 0.25);
}
.btn--ghost:hover { background: rgba(255, 255, 255, 0.16); }

.btn__play {
  display: inline-grid;
  place-items: center;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.18);
  font-size: 10px;
  padding-left: 2px;
}

.hero__meta {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  font-size: 13px;
  color: rgba(255, 255, 255, 0.65);
}
.hero__meta-dot { color: rgba(255, 255, 255, 0.35); }
</style>
