# Vue.js SPA Hello World on AEM

A working Hello World Vue 3 SPA hosted by the AEM author + publish containers in this repo. Two paths to deploy it:

- **Option A — Quick (what we built in `spa-hello/`):** Vite project + `curl` straight into the JCR. No Maven, no archetype, no package install. Useful for experimenting and for understanding what the JCR layout actually needs.
- **Option B — Normal AEM developer flow:** Adobe AEM Project Archetype → Maven `ui.frontend` / `ui.apps` / `ui.content` / `all` modules → content package deployed via Package Manager. This is what a production team ships.

Both produce the **same JCR shape** at runtime; only the build/deploy mechanics differ.

## Target JCR shape (both options produce this)

```
/apps/spa-hello                                 sling:Folder
  components/page                               cq:Component
    page.html                                   HTL: HTML shell + clientlib include
  clientlibs/clientlib-site                     cq:ClientLibraryFolder
    @categories  = ["spa-hello.site"]
    @allowProxy  = true                         ← required for anon /etc.clientlibs on publish
    js.txt, css.txt                             clientlib manifests
    index.js, index.css                         Vite-built Vue bundle

/content/hello                                  cq:Page
  jcr:content                                   cq:PageContent
    @sling:resourceType = "spa-hello/components/page"
    @jcr:title          = "Hello Vue"
```

Request `GET /content/hello.html` →
1. Sling resolves the cq:Page → reads `jcr:content/sling:resourceType` → runs `/apps/spa-hello/components/page/page.html`.
2. The HTL template injects `<script src="/etc.clientlibs/spa-hello/clientlibs/clientlib-site.lc-<hash>-lc.min.js">` and the matching CSS link.
3. Browser fetches the bundle, Vue mounts on `<div id="app">`.

Because the page is rendered by a script (not served as a binary `nt:file`), Sling's `ContentDispositionFilter` does **not** fire, and the response is plain `text/html` — no `Content-Disposition: attachment` to force a download.

---

## Option A — Quick: Vite + `curl` directly to JCR

This is exactly what's in `spa-hello/` in this repo.

### Local project layout

```
spa-hello/
├── package.json                vue@3, vite, @vitejs/plugin-vue
├── vite.config.js              stable filenames (index.js / index.css), no base path
├── index.html                  Vite dev entry — not deployed to AEM
├── src/
│   ├── main.js                 createApp(App).mount('#app')
│   └── App.vue                 single-file component, Hello World + counter
├── aem/                        files that map 1:1 to JCR nodes
│   ├── page.html               HTL template for /apps/spa-hello/components/page
│   ├── js.txt                  clientlib JS manifest
│   └── css.txt                 clientlib CSS manifest
└── dist/                       Vite build output (index.js, index.css)
```

### Build

```bash
cd /home/mli/aem-docker/spa-hello
npm install
npm run build              # → dist/index.js, dist/index.css
```

### Deploy to author

Two HTTP mechanisms come into play:

| Mechanism | Used for | Why |
|---|---|---|
| **Sling POST** (`curl -F`) | Creating typed nodes (`cq:Page`, `cq:Component`, `cq:ClientLibraryFolder`), setting properties | Multipart form maps cleanly to property assignments |
| **WebDAV PUT** (`curl -T`) | Uploading files as `nt:file` at an exact path | Sling POST multipart-with-file gets wrapped in auto-named `N_<timestamp>` folders; PUT lands the file precisely |

Full deploy from scratch:

```bash
AEM=http://localhost:4502
AUTH='-u admin:admin'

# --- /apps/spa-hello/components/page ---
curl -sS $AUTH -F "jcr:primaryType=sling:Folder" "$AEM/apps/spa-hello"
curl -sS $AUTH -F "jcr:primaryType=sling:Folder" "$AEM/apps/spa-hello/components"
curl -sS $AUTH \
  -F "jcr:primaryType=cq:Component" \
  -F "jcr:title=SPA Hello Page" \
  -F "componentGroup=.hidden" \
  "$AEM/apps/spa-hello/components/page"
curl -sS $AUTH -T aem/page.html -H 'Content-Type: text/html' \
  "$AEM/apps/spa-hello/components/page/page.html"

# --- /apps/spa-hello/clientlibs/clientlib-site ---
curl -sS $AUTH -F "jcr:primaryType=sling:Folder" "$AEM/apps/spa-hello/clientlibs"
curl -sS $AUTH \
  -F "jcr:primaryType=cq:ClientLibraryFolder" \
  -F "categories=spa-hello.site" -F "categories@TypeHint=String[]" \
  -F "allowProxy=true" -F "allowProxy@TypeHint=Boolean" \
  "$AEM/apps/spa-hello/clientlibs/clientlib-site"
curl -sS $AUTH -T aem/js.txt   -H 'Content-Type: text/plain'        "$AEM/apps/spa-hello/clientlibs/clientlib-site/js.txt"
curl -sS $AUTH -T aem/css.txt  -H 'Content-Type: text/plain'        "$AEM/apps/spa-hello/clientlibs/clientlib-site/css.txt"
curl -sS $AUTH -T dist/index.js  -H 'Content-Type: application/javascript' "$AEM/apps/spa-hello/clientlibs/clientlib-site/index.js"
curl -sS $AUTH -T dist/index.css -H 'Content-Type: text/css'        "$AEM/apps/spa-hello/clientlibs/clientlib-site/index.css"

# --- /content/hello as cq:Page ---
curl -sS $AUTH \
  -F "jcr:primaryType=cq:Page" \
  -F "jcr:content/jcr:primaryType=cq:PageContent" \
  -F "jcr:content/jcr:title=Hello Vue" \
  -F "jcr:content/sling:resourceType=spa-hello/components/page" \
  "$AEM/content/hello"
```

### Redeploy after Vue edits

```bash
cd /home/mli/aem-docker/spa-hello && npm run build
curl -u admin:admin -T dist/index.js  http://localhost:4502/apps/spa-hello/clientlibs/clientlib-site/index.js
curl -u admin:admin -T dist/index.css http://localhost:4502/apps/spa-hello/clientlibs/clientlib-site/index.css
# Replicate to publish (if publish is set up)
for p in /apps/spa-hello/clientlibs/clientlib-site/index.js \
         /apps/spa-hello/clientlibs/clientlib-site/index.css; do
  curl -u admin:admin -F "cmd=Activate" -F "path=$p" http://localhost:4502/bin/replicate.json
done
```

AEM's clientlib cache-busting selector (`.lc-<hash>-lc.min.{js,css}`) regenerates when content changes, so browser caches don't go stale.

### Replicate to publish

```bash
for p in \
  /apps/spa-hello \
  /apps/spa-hello/components \
  /apps/spa-hello/components/page \
  /apps/spa-hello/components/page/page.html \
  /apps/spa-hello/clientlibs \
  /apps/spa-hello/clientlibs/clientlib-site \
  /apps/spa-hello/clientlibs/clientlib-site/js.txt \
  /apps/spa-hello/clientlibs/clientlib-site/css.txt \
  /apps/spa-hello/clientlibs/clientlib-site/index.js \
  /apps/spa-hello/clientlibs/clientlib-site/index.css \
  /content/hello \
  /content/hello/jcr:content; do
  curl -u admin:admin -F "cmd=Activate" -F "path=$p" http://localhost:4502/bin/replicate.json
done
```

Prerequisites for replication to work (see `aem_docker.md` for the full story):
- Publish container running and on the same docker network as author.
- Publish replication agent enabled at `/etc/replication/agents.author/publish` with `transportUri=http://publish:4503/bin/receive?sling:authRequestLogin=1`, `transportUser=admin`, `transportPassword=admin`, and `userId` cleared (the default `your_replication_user` is a placeholder that fails).

### Verify

```bash
# Author
curl -u admin:admin -I http://localhost:4502/content/hello.html         # 200, no Content-Disposition
curl -u admin:admin http://localhost:4502/content/hello.html | grep src # /etc.clientlibs/spa-hello/...
# Publish (anonymous)
curl -I http://localhost:4503/content/hello.html                         # 200
curl    http://localhost:4503/etc.clientlibs/spa-hello/clientlibs/clientlib-site.js  # JS bundle
```

---

## Option B — Normal: Adobe AEM Project Archetype

This is what an AEM developer/team would do. Same JCR shape ends up in AEM, built and deployed reproducibly from source.

### Toolchain

| Tool | Purpose |
|---|---|
| **Maven 3.9+** | Build orchestration |
| **JDK 11** | Compile Java + run AEM build plugins |
| **Node.js 18+ / npm** | `ui.frontend` JS build |
| **Adobe AEM Project Archetype** | One-shot project scaffold |
| **`autoInstallPackage` profile** | Uploads built `.zip` to a running AEM via `/crx/packmgr/service.jsp` |

### Generate the project

```bash
mvn -B archetype:generate \
  -D archetypeGroupId=com.adobe.aem \
  -D archetypeArtifactId=aem-project-archetype \
  -D archetypeVersion=49 \
  -D appTitle="SPA Hello" \
  -D appId="spa-hello" \
  -D groupId="com.example.spahello" \
  -D frontendModule=general \
  -D includeExamples=n \
  -D aemVersion=cloud
```

Archetype `frontendModule` options: `general` (webpack + plain JS/TS), `react` (full SPA Editor React), `angular` (full SPA Editor Angular). **There is no official Vue option** — for Vue you start with `general` and replace its webpack config with Vite + Vue.

### Resulting structure

```
spa-hello/
├── pom.xml                            parent — declares all modules
├── all/                               aggregator package: bundles ui.apps + ui.content + ui.config
│   └── pom.xml
├── core/                              Java OSGi bundle: servlets, models, schedulers
│   ├── pom.xml
│   └── src/main/java/...
├── ui.apps/                           /apps content as files in JCR_ROOT
│   ├── pom.xml
│   └── src/main/content/jcr_root/apps/spa-hello/
│       ├── components/page/
│       │   ├── .content.xml          ← cq:Component definition
│       │   └── page.html             ← HTL template (same content as Option A)
│       └── clientlibs/clientlib-site/
│           ├── .content.xml          ← cq:ClientLibraryFolder + categories + allowProxy
│           ├── js.txt
│           ├── css.txt
│           ├── js/                    ← populated by ui.frontend build
│           └── css/
├── ui.config/                         /apps/<project>/osgiconfig — runmode-scoped OSGi configs
│   └── src/main/content/jcr_root/apps/spa-hello/osgiconfig/...
├── ui.content/                        /content/spa-hello sample pages
│   └── src/main/content/jcr_root/content/spa-hello/
│       └── .content.xml              ← cq:Page + cq:PageContent referencing the component
├── ui.frontend/                       Vue (or React/Angular) source
│   ├── package.json                   vue, vite, @vitejs/plugin-vue
│   ├── vite.config.js
│   ├── src/
│   │   ├── main.js
│   │   └── App.vue
│   └── (build output copied into ui.apps/.../clientlibs/clientlib-site/js + css)
├── it.tests/                          integration tests against running AEM
└── dispatcher/                        dispatcher config bundle (see dispatcher.md)
```

`.content.xml` files are FileVault-format XML that the build packs back into JCR nodes. Example for the cq:Page:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<jcr:root xmlns:cq="http://www.day.com/jcr/cq/1.0"
          xmlns:jcr="http://www.jcp.org/jcr/1.0"
          xmlns:sling="http://sling.apache.org/jcr/sling/1.0"
          jcr:primaryType="cq:Page">
    <jcr:content
        jcr:primaryType="cq:PageContent"
        jcr:title="Hello Vue"
        sling:resourceType="spa-hello/components/page"/>
</jcr:root>
```

And for the clientlib:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<jcr:root xmlns:cq="http://www.day.com/jcr/cq/1.0"
          xmlns:jcr="http://www.jcp.org/jcr/1.0"
          jcr:primaryType="cq:ClientLibraryFolder"
          allowProxy="{Boolean}true"
          categories="[spa-hello.site]"/>
```

### Wire Vite into `ui.frontend`

Replace webpack with Vite (or keep webpack — both work). The key trick: configure the JS build to write directly into `ui.apps/.../clientlibs/clientlib-site/js/` and `.../css/` so the maven `vault-package` step picks them up.

```js
// ui.frontend/vite.config.js
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: path.resolve(__dirname, '../ui.apps/src/main/content/jcr_root/apps/spa-hello/clientlibs/clientlib-site'),
    emptyOutDir: false,                           // keep js.txt / css.txt
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        entryFileNames: 'js/index.js',
        assetFileNames: (info) => info.name?.endsWith('.css') ? 'css/index.css' : '[name][extname]'
      }
    }
  }
})
```

Hook `npm run build` into the maven build via `frontend-maven-plugin` so `mvn install` triggers it.

### Build & deploy

```bash
# Author only
mvn clean install -PautoInstallPackage              # builds + uploads .zip via package manager

# Publish only
mvn clean install -PautoInstallPackagePublish

# Both
mvn clean install -PautoInstallPackage -PautoInstallPackagePublish
```

`autoInstallPackage` uses the `aem-maven-plugin` to POST to `http://localhost:4502/crx/packmgr/service.jsp` and installs the package immediately. The package itself is a `.zip` at `all/target/spa-hello.all-<version>.zip`.

### Promote between environments

The same `.zip` from `all/target/` is uploaded to higher environments via Package Manager UI or CI/CD (e.g. Cloud Manager). No file-by-file curling — one artifact promotes through dev → stage → prod.

---

## When to use which

| | Option A (quick) | Option B (archetype) |
|---|---|---|
| Time to first render | 5 minutes | 30–60 minutes (toolchain setup) |
| External dependencies | `node` + `curl` | `mvn`, JDK, Maven plugins, npm |
| Deployment artifact | none — direct JCR writes | versioned `.zip` content package |
| Promotable between environments | no — would re-curl each | yes — same `.zip` to stage/prod |
| Source of truth | JCR + `aem/` files | git working tree (everything in git) |
| Integrates with Cloud Manager / CI | no | yes |
| Java backend (servlets, models) | no | yes (`core/` module) |
| Right for | spikes, learning JCR, dev sandbox | real projects |

A reasonable rule: **prototype with A, ship with B**. The JCR shape you converge on in A becomes the `.content.xml` files in B.

---

## Common pitfalls (learned the hard way in Option A)

| Symptom | Cause | Fix |
|---|---|---|
| `curl -F "*=@file"` creates an `nt:file` inside an auto-named `N_<timestamp>` folder | Sling POST treats `*` as auto-name; multipart-with-file may also get intercepted | Use `curl -T file path` (WebDAV PUT) for exact-path uploads |
| HTML downloads as attachment instead of rendering | Sling `ContentDispositionFilter` forces `Content-Disposition: attachment` on `nt:file`s under `/content` with `jcr:data` | Render via a `cq:Page` + HTL script (no `jcr:data`) — what Option A's component does |
| JS/CSS 404 on publish for anonymous users | `/apps` is not anon-readable on publish by default | Set `allowProxy=true` on the `cq:ClientLibraryFolder` → served at `/etc.clientlibs/...` which IS anon-readable |
| `Replication triggered, but no agent found! for path /content/hello` | Publish replication agent disabled, or no publish container exists | Start publish, enable agent, set transportUri, clear `userId` placeholder |
| `Error: Replicaiton Agent [publish] has invalid agent userId [your_replication_user]` (typo is in AEM) | Default agent has placeholder `userId=your_replication_user` | `curl -F "userId=" .../publish/jcr:content` |
| Author can't reach publish for replication | Author and publish on different docker networks | `docker network connect aem-net aem-publish` (or unify in compose) |

---

## Related docs

- `aem_docker.md` — author + publish container setup
- `cloudflared.md` — Cloudflare Tunnel for public access
- `dispatcher.md` — putting Adobe Dispatcher in front of publish
