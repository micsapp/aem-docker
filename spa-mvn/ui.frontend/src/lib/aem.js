// Tiny fetch client for AEM Content Fragments served as Sling JSON.
//
// In dev (npm run dev): Vite proxies /content/* → http://localhost:4502 (see vite.config.js).
// In production (mounted in clientlib): same-origin against publish, no proxy needed.
//
// Each fragment lives at /content/dam/spa-mvn/cf/<id>; the master variation data is at
// .../<id>/jcr:content/data/master  → reachable via Sling default JSON renderer with .json

const BASE = '/content/dam/spa-mvn/cf'

async function getJson(path) {
  const res = await fetch(path, { credentials: 'same-origin' })
  if (!res.ok) throw new Error(`${path} → HTTP ${res.status}`)
  return res.json()
}

function master(fragmentNode, path) {
  // strip JCR housekeeping; tag with _path so edit-mode knows what to PATCH
  const m = fragmentNode?.['jcr:content']?.data?.master || {}
  const out = { _path: path }
  for (const k of Object.keys(m)) {
    if (!k.startsWith('jcr:') && !k.startsWith('sling:') && !k.startsWith('cq:')) out[k] = m[k]
  }
  return out
}

export async function fetchHero() {
  return master(await getJson(`${BASE}/hero.4.json`), 'hero')
}

export async function fetchCtaBanner() {
  return master(await getJson(`${BASE}/cta_banner.4.json`), 'cta_banner')
}

export async function fetchFeatures() {
  const folder = await getJson(`${BASE}/features.4.json`)
  return Object.keys(folder)
    .filter((k) => k.startsWith('feature_'))
    .sort()
    .map((k) => master(folder[k], `features/${k}`))
}

export async function fetchStats() {
  const folder = await getJson(`${BASE}/stats.4.json`)
  return Object.keys(folder)
    .filter((k) => k.startsWith('stat_'))
    .sort()
    .map((k) => master(folder[k], `stats/${k}`))
}

export async function fetchAll() {
  const [hero, features, stats, ctaBanner] = await Promise.all([
    fetchHero(),
    fetchFeatures(),
    fetchStats(),
    fetchCtaBanner()
  ])
  return { hero, features, stats, ctaBanner }
}
