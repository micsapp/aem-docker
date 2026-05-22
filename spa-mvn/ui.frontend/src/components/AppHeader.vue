<script setup>
import { ref } from 'vue'

const open = ref(false)

const nav = [
  { label: 'Products', href: '#' },
  { label: 'Solutions', href: '#' },
  { label: 'Customers', href: '#' },
  { label: 'Pricing', href: '#' },
  { label: 'Resources', href: '#' }
]
</script>

<template>
  <header class="hdr">
    <div class="container hdr__inner">
      <a href="#" class="hdr__brand">
        <span class="hdr__mark">SM</span>
        <span class="hdr__name">SPA Mountain</span>
      </a>

      <nav class="hdr__nav" :class="{ 'hdr__nav--open': open }">
        <a v-for="item in nav" :key="item.label" :href="item.href" class="hdr__link">
          {{ item.label }}
        </a>
      </nav>

      <div class="hdr__actions">
        <a href="#" class="hdr__signin">Sign in</a>
        <a href="#" class="hdr__cta">Start free trial</a>
        <button class="hdr__menu" @click="open = !open" aria-label="Toggle menu">
          <span></span><span></span><span></span>
        </button>
      </div>
    </div>
  </header>
</template>

<style scoped>
.hdr {
  position: sticky;
  top: 0;
  z-index: 100;
  background: rgba(255, 255, 255, 0.92);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid #ececec;
}

.hdr__inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 64px;
}

.hdr__brand { display: flex; align-items: center; gap: 10px; font-weight: 700; }
.hdr__mark {
  display: inline-grid;
  place-items: center;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: linear-gradient(135deg, #ff3b30, #1473e6);
  color: white;
  font-size: 13px;
  font-weight: 800;
  letter-spacing: 0.5px;
}
.hdr__name { font-size: 16px; }

.hdr__nav {
  display: flex;
  gap: 28px;
}

.hdr__link {
  font-size: 14px;
  font-weight: 500;
  color: #444;
  transition: color 0.15s ease;
}
.hdr__link:hover { color: #1473e6; }

.hdr__actions { display: flex; align-items: center; gap: 16px; }

.hdr__signin { font-size: 14px; font-weight: 500; color: #444; }

.hdr__cta {
  font-size: 14px;
  font-weight: 600;
  padding: 8px 16px;
  border-radius: 999px;
  background: #1a1a1a;
  color: white;
  transition: background 0.15s ease;
}
.hdr__cta:hover { background: #1473e6; }

.hdr__menu {
  display: none;
  flex-direction: column;
  gap: 4px;
  background: transparent;
  border: none;
  padding: 8px;
}
.hdr__menu span {
  display: block;
  width: 20px;
  height: 2px;
  background: #1a1a1a;
  border-radius: 1px;
}

@media (max-width: 880px) {
  .hdr__nav {
    display: none;
    position: absolute;
    top: 64px;
    left: 0;
    right: 0;
    flex-direction: column;
    gap: 0;
    background: white;
    border-bottom: 1px solid #ececec;
    padding: 12px 24px;
  }
  .hdr__nav--open { display: flex; }
  .hdr__link { padding: 12px 0; }
  .hdr__signin { display: none; }
  .hdr__menu { display: flex; }
}
</style>
