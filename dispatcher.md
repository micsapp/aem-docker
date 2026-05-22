# AEM Dispatcher Setup

How to put **Adobe Dispatcher** in front of the publish container in this docker stack — what it is, what it changes, the exact files and compose service we add, and how to verify it.

## Why dispatcher

The publish JVM is a content rendering engine, not an internet-facing HTTP server. In a real AEM topology nobody hits publish directly — there is always a dispatcher (or a CDN backed by dispatcher) in between. Without dispatcher:

| Concern | Raw publish | Behind dispatcher |
|---|---|---|
| `*.json` selectors leak JCR data (`/content.infinity.json`) | reachable | blocked by filters |
| `/system/console`, `/crx`, `/bin/*` | reachable | blocked by filters |
| Every request re-renders in the JVM | always | cache hit ≈ disk read |
| URL structure (`/content/site/en/home.html`) | exposed | rewritable to `/en/home` |
| Cache invalidation on publish | n/a | flush agent → invalidate.cache |

## What it actually is

Dispatcher is **Apache HTTPD + a binary module** (`mod_dispatcher.so`). Not a JVM app, not a separate process running a jar.

```
adobe/aem-ethos/dispatcher-publish:latest        ← Docker image (≈100 MB)
├── /usr/sbin/httpd                              (Apache HTTPD 2.4)
├── /etc/httpd/modules/mod_dispatcher.so         (the binary module)
├── /etc/httpd/conf/                             (Apache base config)
└── /mnt/dev/src/                                (your config bundle, mounted in)
```

RAM footprint ~100 MB vs publish's ~3 GB. Configuration is plain text in Apache-ish syntax (`.any` / `.farm` / `.vhost` files).

## Request flow

```
Browser ──► dispatcher:8080
              │
              ├─ vhost match: does any VirtualHost claim this Host header?
              ├─ farm match: which farm handles this hostname?
              ├─ filter check: is this URL + method allowed?
              │     deny  → 404
              ├─ cache check: file exists under /mnt/var/www/...?
              │     hit   → serve file (no publish round-trip)
              └─ miss → proxy to publish:4503
                          ↓
                   write body to cache dir (if cacheable)
                          ↓
                   send response to browser
```

## Cache invalidation flow

```
Author author UI ──"Publish"──► author Replicator
                                     │
                                     ├─► publish agent (durbo POST) → publish:4503/bin/receive
                                     │                                       (writes content to JCR)
                                     │
                                     └─► flush agent  (HTTP POST)   → dispatcher:80/dispatcher/invalidate.cache
                                                                            (deletes matching cache files)
```

The flush agent is a built-in replication agent on author. We point its `transportUri` at the dispatcher's invalidate endpoint, and AEM fires it whenever content is replicated.

## File layout in this repo

```
aem-docker/
├── dispatcher/
│   └── src/                                        mounted as /mnt/dev/src in container
│       ├── conf.d/
│       │   ├── available_vhosts/
│       │   │   └── publish.vhost                   Apache VirtualHost (hostname → farm)
│       │   ├── enabled_vhosts/
│       │   │   └── publish.vhost                   symlink → ../available_vhosts/publish.vhost
│       │   ├── rewrites/
│       │   │   └── rewrite.rules                   URL rewriting (/ → /content/hello.html)
│       │   └── variables/
│       │       └── global.vars                     shared env vars
│       ├── conf.dispatcher.d/
│       │   ├── available_farms/
│       │   │   └── publish.farm                    backend, cache, filters per farm
│       │   ├── enabled_farms/
│       │   │   └── publish.farm                    symlink → ../available_farms/publish.farm
│       │   ├── cache/
│       │   │   └── rules.any                       what to cache
│       │   ├── filters/
│       │   │   └── filters.any                     URL allow/deny rules
│       │   ├── renders/
│       │   │   └── default_renders.any             render targets (publish backend)
│       │   ├── clientheaders/
│       │   │   └── default_clientheaders.any       request headers forwarded to publish
│       │   └── virtualhosts/
│       │       └── virtualhosts.any                hostnames this farm serves
│       └── opt-in/
│           └── USE_SOURCES_DIRECTLY                tells image: use /mnt/dev/src as-is, don't normalize
└── docker-compose.yml                              new `dispatcher` service added
```

## Key config files

### `dispatcher/src/conf.d/available_vhosts/publish.vhost`

Apache VirtualHost that owns the public hostname.

```apache
<VirtualHost *:80>
    ServerName "publish"
    ServerAlias "aem-publish.micstec.com" "localhost"

    DocumentRoot "/mnt/var/www/html"

    <Directory "/mnt/var/www/html">
        AllowOverride None
        Require all granted
    </Directory>

    Include conf.d/rewrites/rewrite.rules
</VirtualHost>
```

### `dispatcher/src/conf.d/rewrites/rewrite.rules`

Rewrites `/` to the SPA page so the bare hostname renders.

```apache
RewriteEngine On
RewriteRule "^/?$" "/content/hello.html" [PT,L]
```

### `dispatcher/src/conf.dispatcher.d/available_farms/publish.farm`

The farm: backend host, cache dir, filter set.

```
/publishfarm {
    /clientheaders { $include "../clientheaders/default_clientheaders.any" }
    /virtualhosts  { $include "../virtualhosts/virtualhosts.any" }
    /renders       { $include "../renders/default_renders.any" }
    /filter        { $include "../filters/filters.any" }
    /cache {
        /docroot "/mnt/var/www/html"
        /statfileslevel "2"
        /allowAuthorized "0"
        /serveStaleOnError "1"
        /rules { $include "../cache/rules.any" }
        /invalidate {
            /0000 { /glob "*" /type "allow" }
        }
        /allowedClients {
            /0000 { /glob "*"        /type "deny" }
            /0001 { /glob "127.0.0.1" /type "allow" }
            /0002 { /glob "172.*"    /type "allow" }   # docker bridge range
        }
    }
}
```

### `dispatcher/src/conf.dispatcher.d/filters/filters.any`

Default-deny, then allow only what we want public.

```
/0001 { /type "deny"  /glob "*" }

# allow our SPA page
/0100 { /type "allow" /method "GET" /url "/content/hello*" }

# allow clientlibs proxy
/0101 { /type "allow" /method "GET" /url "/etc.clientlibs/*" }

# block dangerous paths explicitly even if a later rule re-allows
/9000 { /type "deny"  /url "/system/*" }
/9001 { /type "deny"  /url "/crx/*" }
/9002 { /type "deny"  /url "/bin/*" }
/9003 { /type "deny"  /url "/apps/*" }
/9004 { /type "deny"  /url "/libs/*" }
/9005 { /type "deny"  /url "*.json" }
/9006 { /type "deny"  /url "*.infinity.json" }
/9007 { /type "deny"  /url "*.tidy.json" }
```

### `dispatcher/src/conf.dispatcher.d/renders/default_renders.any`

Where to send cache misses.

```
/rend0 {
    /hostname "publish"
    /port     "4503"
}
```

### `dispatcher/src/conf.dispatcher.d/virtualhosts/virtualhosts.any`

Which `Host:` headers this farm serves.

```
"aem-publish.micstec.com"
"localhost"
"publish"
"*"
```

### `dispatcher/src/conf.dispatcher.d/cache/rules.any`

What to cache. Conservative for now.

```
/0000 { /glob "*"      /type "deny" }
/0010 { /glob "*.html" /type "allow" }
/0011 { /glob "*.css"  /type "allow" }
/0012 { /glob "*.js"   /type "allow" }
/0013 { /glob "*.png"  /type "allow" }
/0014 { /glob "*.jpg"  /type "allow" }
/0015 { /glob "*.svg"  /type "allow" }
/0016 { /glob "*.woff*" /type "allow" }
```

### `dispatcher/src/conf.dispatcher.d/clientheaders/default_clientheaders.any`

Request headers forwarded to publish.

```
"Cookie"
"Authorization"
"User-Agent"
"Accept-Language"
"X-Forwarded-For"
"X-Forwarded-Host"
"X-Forwarded-Proto"
```

## Compose service

Added to `docker-compose.yml`:

```yaml
  dispatcher:
    image: adobe/aem-ethos/dispatcher-publish:latest
    container_name: aem-dispatcher
    depends_on: [publish]
    ports:
      - "8080:80"
    environment:
      - REMOTE_HOST=publish
      - REMOTE_PORT=4503
      - DISP_LOG_LEVEL=warn
      - REWRITE_LOG_LEVEL=warn
    volumes:
      - ./dispatcher/src:/mnt/dev/src:ro
    restart: unless-stopped
    networks: [default]
```

(The author + publish containers must be on the same docker network as `dispatcher` so it can resolve `publish:4503`.)

## Author-side: flush agent

After dispatcher is up, enable the built-in flush agent on author so AEM invalidates cache when content is replicated:

```bash
curl -u admin:admin \
  -F "enabled=true" \
  -F "userId=" \
  -F "transportUri=http://dispatcher:80/dispatcher/invalidate.cache" \
  -F "transportUser=" \
  -F "transportPassword=" \
  http://localhost:4502/etc/replication/agents.author/flush/jcr:content
```

The flush request POSTs a list of paths with header `CQ-Action: Activate` and `CQ-Handle: <path>`. Dispatcher deletes the matching cached files.

## Cloudflare tunnel swap

Once dispatcher is up and verified, point the public hostname at the dispatcher port instead of publish:

```yaml
# ~/.cloudflared/config.yml
- hostname: aem-publish.micstec.com
  service: http://localhost:8080     # was http://localhost:4503
```

Restart the tmux cloudflared session. Now `https://aem-publish.micstec.com/` goes through dispatcher, with filters and cache.

## Verify

```bash
# Bare URL now redirects to the SPA
curl -sSI http://localhost:8080/         # 302 → /content/hello.html
curl -sSL http://localhost:8080/         # 200 SPA HTML

# Cache works (second hit faster, X-Dispatcher header on hit)
time curl -sS http://localhost:8080/content/hello.html >/dev/null
time curl -sS http://localhost:8080/content/hello.html >/dev/null   # ~10x faster

# Filters block dangerous paths
curl -sSI http://localhost:8080/system/console/bundles  # 404
curl -sSI http://localhost:8080/content/hello.json       # 404
curl -sSI http://localhost:8080/crx/de                   # 404

# Cache invalidation works
# 1) edit /content/hello/jcr:content title, replicate
# 2) curl /content/hello.html on dispatcher — should show updated content
```

## Troubleshooting

- **`Could not connect to remote host publish:4503`** — dispatcher container isn't on the same docker network as publish. Inspect with `docker network inspect aem-net` and connect with `docker network connect aem-net aem-dispatcher`.
- **All requests 404** — vhost ServerName/ServerAlias doesn't match the Host header. Add the hostname to both `publish.vhost` and `virtualhosts.any`, then `docker compose restart dispatcher`.
- **Cache not populating** — check `/cache/allowedClients` matches the IP that's POSTing (the publish container). Add `/0003 { /glob "172.*" /type "allow" }` if needed.
- **Flush agent fails with 403** — `/cache/allowedClients` must allow the publish container's IP. The invalidate endpoint is IP-gated.
- **Page renders but JS/CSS 404** — `/etc.clientlibs/*` filter rule missing or denied. Confirm `/0101` rule exists in filters.any.
- **Cache shows stale content after publish** — flush agent disabled, or transportUri wrong, or `/cache/invalidate` rules don't match the changed path. Check `crx-quickstart/logs/replication.log` on author.

## What this setup intentionally does NOT do

- TLS termination — Cloudflare handles HTTPS at the edge; origin is HTTP-only.
- Multiple farms — single `/publishfarm`. Real sites often have per-tenant or per-region farms.
- Auth — no Cloudflare Access; rely on filter rules + the fact that publish enforces ACLs.
- Production cache headers — no explicit `Cache-Control` / `Expires` shaping; relies on AEM defaults. Add via Apache `Header set` in the vhost when needed.
- Health checks — no `/healthz` endpoint; rely on `docker compose ps`.

## Related docs

- `aem_docker.md` — author/publish container setup
- `cloudflared.md` — tunnel that fronts both author and (post-setup) dispatcher
- Adobe upstream docs: https://experienceleague.adobe.com/docs/experience-manager-dispatcher/using/getting-started/overview.html
