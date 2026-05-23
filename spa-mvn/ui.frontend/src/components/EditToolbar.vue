<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import {
  editMode, hasAuth, setAdminPassword, clearAdminPassword,
  dirtyPaths, publishFragment, clearDirty
} from '../lib/edit.js'

const password = ref('')
const publishing = ref(false)
const flash = ref('')

const onAuthorOrigin = computed(() =>
  typeof window !== 'undefined' &&
  (window.location.port === '4502' || /localhost:4502/.test(window.location.host))
)

function signIn() {
  if (!password.value) return
  setAdminPassword(password.value)
  password.value = ''
}

async function publishAll() {
  if (dirtyPaths.value.length === 0) return
  publishing.value = true
  flash.value = ''
  try {
    for (const p of dirtyPaths.value.slice()) {
      await publishFragment(p)
      clearDirty(p)
    }
    flash.value = 'Published'
    setTimeout(() => { flash.value = '' }, 3500)
  } catch (err) {
    flash.value = 'Failed: ' + (err.message || err)
    setTimeout(() => { flash.value = '' }, 6000)
  } finally {
    publishing.value = false
  }
}

function exitEdit() {
  const url = new URL(window.location.href)
  url.searchParams.delete('edit')
  window.location.href = url.toString()
}

onMounted(() => { if (editMode.value) document.body.classList.add('edit-mode') })
onUnmounted(() => { document.body.classList.remove('edit-mode') })
</script>

<template>
  <div v-if="editMode" class="et">
    <div class="et__inner">
      <span class="et__tag">EDIT MODE</span>

      <span v-if="!onAuthorOrigin" class="et__warn">
        ⚠ open this URL on <code>localhost:4502</code> (author) — publish + dispatcher block writes
      </span>

      <template v-if="onAuthorOrigin && !hasAuth">
        <input
          v-model="password"
          type="password"
          placeholder="admin password"
          class="et__input"
          @keyup.enter="signIn"
        />
        <button class="et__btn" @click="signIn">Sign in</button>
      </template>

      <template v-else-if="hasAuth">
        <span class="et__status" v-if="dirtyPaths.length">
          {{ dirtyPaths.length }} unpublished
        </span>
        <button
          class="et__btn"
          :disabled="dirtyPaths.length === 0 || publishing"
          @click="publishAll"
        >{{ publishing ? 'Publishing…' : 'Publish all' }}</button>
        <button class="et__btn et__btn--ghost" @click="clearAdminPassword">Sign out</button>
        <span v-if="flash" class="et__flash">{{ flash }}</span>
      </template>

      <button class="et__close" @click="exitEdit" title="Exit edit mode">✕</button>
    </div>
  </div>
</template>

<style>
body.edit-mode { padding-top: 50px; }
</style>

<style scoped>
.et {
  position: fixed; top: 0; left: 0; right: 0; z-index: 9999;
  background: linear-gradient(90deg, #161629, #2d1a4e);
  color: white;
  padding: 10px 16px;
  box-shadow: 0 2px 14px rgba(0,0,0,0.3);
  font-size: 13px;
  font-family: -apple-system, system-ui, sans-serif;
}
.et__inner { max-width: 1200px; margin: 0 auto; display: flex; align-items: center; gap: 12px; }
.et__tag { font-weight: 800; letter-spacing: 0.08em; font-size: 11px; color: #b5c3ff; }
.et__input {
  padding: 6px 10px; border-radius: 6px;
  border: 1px solid rgba(255,255,255,0.2);
  background: rgba(255,255,255,0.08); color: white;
  font-size: 13px; min-width: 180px;
}
.et__btn {
  padding: 6px 14px; border-radius: 6px; border: none;
  background: #1473e6; color: white; cursor: pointer;
  font-weight: 600; font-size: 13px;
}
.et__btn:disabled { background: rgba(255,255,255,0.15); cursor: not-allowed; }
.et__btn--ghost { background: rgba(255,255,255,0.10); }
.et__btn--ghost:hover { background: rgba(255,255,255,0.18); }
.et__status { color: #ffd166; font-weight: 600; }
.et__flash  { color: #6ee7a8; font-weight: 600; }
.et__warn   { color: #ffd166; }
.et__warn code { background: rgba(255,255,255,0.12); padding: 1px 6px; border-radius: 4px; }
.et__close {
  margin-left: auto;
  background: transparent; color: white;
  border: 1px solid rgba(255,255,255,0.25); border-radius: 6px;
  width: 28px; height: 28px; cursor: pointer; font-size: 14px;
}
.et__close:hover { background: rgba(255,255,255,0.1); }
</style>
