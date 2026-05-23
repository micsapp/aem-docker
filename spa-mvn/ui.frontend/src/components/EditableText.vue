<script setup>
import { ref, watch, computed } from 'vue'
import { editMode, hasAuth, saveField, markDirty } from '../lib/edit.js'

const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  fragmentPath: { type: String, required: true },
  fieldName:    { type: String, required: true },
  tag:          { type: String, default: 'span' },
  placeholder:  { type: String, default: '' }
})
const emit = defineEmits(['update:modelValue'])

const localValue = ref(String(props.modelValue ?? ''))
const saving = ref(false)
const errMsg = ref(null)

watch(() => props.modelValue, (v) => { localValue.value = String(v ?? '') })

const isEditing = computed(() => editMode.value && hasAuth.value)
const placeholderActive = computed(() => isEditing.value && !localValue.value)

async function onBlur(e) {
  const newVal = e.target.innerText.trim()
  if (newVal === String(props.modelValue ?? '')) return
  saving.value = true
  errMsg.value = null
  try {
    await saveField(props.fragmentPath, props.fieldName, newVal)
    emit('update:modelValue', newVal)
    localValue.value = newVal
    markDirty(props.fragmentPath)
  } catch (err) {
    errMsg.value = err.message || String(err)
    e.target.innerText = props.modelValue
    console.error('[edit]', err)
  } finally {
    saving.value = false
  }
}

function onFocus(e) {
  if (placeholderActive.value) e.target.innerText = ''
}
function onKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); e.target.blur() }
  if (e.key === 'Escape') { e.target.innerText = props.modelValue; e.target.blur() }
}
</script>

<template>
  <component
    :is="tag"
    v-if="isEditing"
    contenteditable="true"
    spellcheck="false"
    class="editable"
    :class="{ saving, error: !!errMsg, placeholder: placeholderActive }"
    :title="errMsg || `Click to edit · ${fragmentPath}.${fieldName}`"
    @blur="onBlur"
    @focus="onFocus"
    @keydown="onKeydown"
    v-text="placeholderActive ? (placeholder || fieldName) : localValue"
  />
  <component v-else :is="tag" v-text="localValue" />
</template>

<style scoped>
.editable {
  outline: 1px dashed rgba(20, 115, 230, 0.45);
  outline-offset: 3px;
  background: rgba(20, 115, 230, 0.04);
  border-radius: 3px;
  cursor: text;
  transition: outline-color 0.15s ease, background 0.15s ease;
  min-width: 0.6em;
}
.editable:hover  { outline-color: rgba(20, 115, 230, 0.85); background: rgba(20, 115, 230, 0.08); }
.editable:focus  { outline: 2px solid #1473e6; background: rgba(20, 115, 230, 0.14); }
.editable.saving { outline-color: #ffa500; background: rgba(255, 165, 0, 0.1); }
.editable.error  { outline-color: #ff3b30; background: rgba(255, 59, 48, 0.12); }
.editable.placeholder { color: rgba(120, 120, 120, 0.7); font-style: italic; }
</style>
