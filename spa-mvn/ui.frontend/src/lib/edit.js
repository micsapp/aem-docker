// Tiny in-page editor for spa-mvn Content Fragments.
//
// Activated by ?edit=1. PATCHes field values into
// /content/dam/spa-mvn/cf/<frag>/jcr:content/data/master via Sling POST,
// then optionally activates the fragment via /bin/replicate.json.
//
// Auth: HTTP Basic. Password is kept in sessionStorage so a reload survives
// without persisting cross-session. Editing only works against author
// (localhost:4502) — publish + dispatcher block /content/dam writes by design.

import { ref, computed } from 'vue'

const params = new URLSearchParams(typeof window !== 'undefined' ? window.location.search : '')
export const editMode = computed(() => params.get('edit') === '1')

const STORE_KEY = 'spa-mvn:admin-pwd'
const passwordRef = ref(
  typeof sessionStorage !== 'undefined' ? sessionStorage.getItem(STORE_KEY) || '' : ''
)
export const hasAuth = computed(() => Boolean(passwordRef.value))

export function setAdminPassword(pwd) {
  passwordRef.value = pwd
  sessionStorage.setItem(STORE_KEY, pwd)
}
export function clearAdminPassword() {
  passwordRef.value = ''
  sessionStorage.removeItem(STORE_KEY)
}

function authHeader() {
  if (!passwordRef.value) throw new Error('Sign in as admin first')
  return { Authorization: 'Basic ' + btoa('admin:' + passwordRef.value) }
}

const BASE = '/content/dam/spa-mvn/cf'

export async function saveField(fragmentPath, fieldName, value) {
  const url = `${BASE}/${fragmentPath}/jcr:content/data/master`
  const form = new FormData()
  form.set(fieldName, value)
  const res = await fetch(url, {
    method: 'POST',
    headers: authHeader(),
    body: form,
    credentials: 'same-origin'
  })
  if (!res.ok) throw new Error(`Save ${fragmentPath}.${fieldName} failed: HTTP ${res.status}`)
}

export async function publishFragment(fragmentPath) {
  const form = new FormData()
  form.set('path', `${BASE}/${fragmentPath}`)
  form.set('cmd', 'Activate')
  const res = await fetch('/bin/replicate.json', {
    method: 'POST',
    headers: authHeader(),
    body: form,
    credentials: 'same-origin'
  })
  if (!res.ok) throw new Error(`Publish ${fragmentPath} failed: HTTP ${res.status}`)
}

// Pending-changes tracking so the toolbar can publish in one click.
const dirtySet = ref(new Set())
export const dirtyPaths = computed(() => [...dirtySet.value])
export function markDirty(path) { dirtySet.value = new Set([...dirtySet.value, path]) }
export function clearDirty(path) {
  const next = new Set(dirtySet.value); next.delete(path); dirtySet.value = next
}
export function clearAllDirty() { dirtySet.value = new Set() }
