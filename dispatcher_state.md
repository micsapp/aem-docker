# Dispatcher Setup — Current State

Snapshot of where we are in adding Adobe Dispatcher in front of the publish container. Resume from here.

Last updated: 2026-05-21

## Status

| # | Task | Status |
|---|---|---|
| 16 | Write `dispatcher.md` design doc | ✅ done |
| 17 | Obtain dispatcher binary / image | ⏸ **BLOCKED — waiting on user** |
| 18 | Create `dispatcher/src/` config bundle | pending |
| 19 | Add `dispatcher` service to `docker-compose.yml` | pending |
| 20 | Configure flush agent on author | pending |
| 21 | Verify dispatcher serves and caches | pending |

## The blocker

Adobe's dispatcher module (`mod_dispatcher.so`) is proprietary. Three ways to obtain it; we picked the SDK-tarball path because the user has Adobe SDK access:

1. ❌ `docker pull adobe/aem-ethos/dispatcher-publish` — **403, requires Adobe registry login** (verified)
2. ❌ `docker pull adobe/aemcs-dispatcher-publish-amd64` — **403, requires Adobe registry login** (verified)
3. ⏸ **Extract from Adobe SDK dispatcher tools tarball** — chosen path, file not yet on host

User has confirmed they have the Linux dispatcher tools as a **`.sh` file** (Adobe distributes it as a self-extracting shell script, typical name `aem-sdk-dispatcher-tools-<version>-unix.sh`), but it has not been transferred to this machine yet.

**To resume:** user places the `.sh` somewhere on this host and tells the agent the path.

## What already exists

| Artifact | Path | State |
|---|---|---|
| Design doc | `/home/mli/aem-docker/dispatcher.md` | written, covers all phases |
| SPA example doc | `/home/mli/aem-docker/spa_example.md` | written, includes link to dispatcher.md |
| Author container | `aem-author` on `aem-net` (172.19.0.2) | running |
| Publish container | `aem-publish` on `aem-docker_default` AND `aem-net` | running |
| SPA page on author | `cq:Page` at `/content/hello` | rendering 200 at `/content/hello.html` |
| SPA page on publish | replicated | rendering 200 anonymously |
| Clientlib `allowProxy` | `/apps/spa-hello/clientlibs/clientlib-site` | `true` — served at `/etc.clientlibs/...` |
| Replication agents | publish agent enabled, flush agent **not yet configured** | publish works, flush pending dispatcher |

## What changes when dispatcher is added

| Component | Before | After |
|---|---|---|
| `docker-compose.yml` | author + publish | author + publish + **dispatcher** (port 8080:80) |
| Public entrypoint | `http://localhost:4503` (publish direct) | `http://localhost:8080` (dispatcher → publish) |
| Cloudflare tunnel | `aem-publish.micstec.com → :4503` (when configured) | `aem-publish.micstec.com → :8080` |
| Flush replication agent on author | not configured | enabled → `http://dispatcher:80/dispatcher/invalidate.cache` |
| Cache invalidation flow | n/a | author replicates → publish stores + fires flush → dispatcher deletes cached files |
| Bare URL `/` | 403 → 404 chain on publish | rewritten by dispatcher vhost to `/content/hello.html` |
| Filters | none (publish exposes everything) | default-deny in `filters.any`, allow only `/content/hello*` + `/etc.clientlibs/*` |

## Resume plan (when `.sh` arrives)

### Step 1 — Unpack the dispatcher tools (task #17)

Adobe's `.sh` is a self-extracting installer:

```bash
chmod +x /path/to/aem-sdk-dispatcher-tools-*-unix.sh
mkdir -p /home/mli/aem-docker/dispatcher/tools
cd /home/mli/aem-docker/dispatcher/tools
/path/to/aem-sdk-dispatcher-tools-*-unix.sh
```

Expected output (typical structure of Adobe's dispatcher tools):

```
dispatcher/tools/
├── bin/
│   ├── dispatcher_run.sh         convenience launcher (uses Adobe image — won't help us)
│   └── docker_run.sh             same — wraps adobe image
├── src/                          ← starter config bundle (use this!)
│   ├── conf.d/
│   ├── conf.dispatcher.d/
│   └── opt-in/
├── lib/
│   └── mod_dispatcher.so         ← the binary module (this is what we need)
└── version.info
```

Goal: identify two things —
1. The `.so` file (linux amd64 build of `mod_dispatcher.so`) — needed if we build our own image
2. The `src/` directory — starter config we'll adapt

### Step 2 — Build a local dispatcher image around `httpd:2.4` (task #17 continued)

Since we can't pull Adobe's image, we wrap their `.so` in a stock Apache:

```dockerfile
# /home/mli/aem-docker/dispatcher/Dockerfile
FROM httpd:2.4

# Copy Adobe's binary module into Apache's modules dir
COPY tools/lib/mod_dispatcher.so /usr/local/apache2/modules/mod_dispatcher.so

# Base httpd config: load dispatcher module + include /mnt/dev/src
RUN sed -i \
      -e '/LoadModule.*proxy_module/a LoadModule dispatcher_module modules/mod_dispatcher.so' \
      -e '$a Include /mnt/dev/src/conf.d/enabled_vhosts/*.vhost' \
      -e '$a <IfModule dispatcher_module>\n    DispatcherConfig /mnt/dev/src/conf.dispatcher.d/dispatcher.any\n    DispatcherLog /proc/self/fd/2\n    DispatcherLogLevel warn\n</IfModule>' \
      /usr/local/apache2/conf/httpd.conf

# Create cache dir
RUN mkdir -p /mnt/var/www/html && chmod 777 /mnt/var/www/html

EXPOSE 80
```

Build:

```bash
cd /home/mli/aem-docker/dispatcher
docker build -t aem-dispatcher:local .
```

Note: the exact `sed` directives may need adjustment depending on the upstream httpd config layout. The important pieces are:
- `LoadModule dispatcher_module modules/mod_dispatcher.so`
- Top-level `DispatcherConfig` pointing at our `dispatcher.any`
- Including our vhost files

If the `.so` doesn't load (ABI mismatch, missing symbols), fallback path: try Apache 2.4 specifically pinned to a version matching what Adobe built against — check `tools/version.info` for the httpd version Adobe used.

### Step 3 — Author the `src/` bundle (task #18)

Don't reinvent — start from the `src/` Adobe ships in the tools tarball, then overlay our customizations from `dispatcher.md`:

```bash
mkdir -p /home/mli/aem-docker/dispatcher/src
cp -r /home/mli/aem-docker/dispatcher/tools/src/* /home/mli/aem-docker/dispatcher/src/
```

Then edit per `dispatcher.md` "Key config files" section:

| File | What we override |
|---|---|
| `conf.d/available_vhosts/publish.vhost` | `ServerName publish`, `ServerAlias aem-publish.micstec.com localhost`, include rewrite rules |
| `conf.d/enabled_vhosts/publish.vhost` | symlink → `../available_vhosts/publish.vhost` |
| `conf.d/rewrites/rewrite.rules` | `RewriteRule "^/?$" "/content/hello.html" [PT,L]` |
| `conf.dispatcher.d/available_farms/publish.farm` | backend `publish:4503`, cache dir `/mnt/var/www/html`, allowedClients `172.*` |
| `conf.dispatcher.d/enabled_farms/publish.farm` | symlink |
| `conf.dispatcher.d/filters/filters.any` | default deny, allow `/content/hello*` + `/etc.clientlibs/*`, explicit deny `/system/*` `/crx/*` `/bin/*` `*.json` |
| `conf.dispatcher.d/renders/default_renders.any` | `hostname "publish"`, `port "4503"` |
| `conf.dispatcher.d/virtualhosts/virtualhosts.any` | `"aem-publish.micstec.com"`, `"localhost"`, `"publish"` |
| `conf.dispatcher.d/cache/rules.any` | deny `*`, allow `*.html`, `*.css`, `*.js`, image extensions |
| `conf.dispatcher.d/clientheaders/default_clientheaders.any` | keep upstream defaults |
| `opt-in/USE_SOURCES_DIRECTLY` | touch (empty file, signals image to use src/ as-is) |

(Each file's exact content is in `dispatcher.md`.)

### Step 4 — Compose service (task #19)

Add to `/home/mli/aem-docker/docker-compose.yml`:

```yaml
  dispatcher:
    image: aem-dispatcher:local                # built in step 2
    container_name: aem-dispatcher
    depends_on: [publish]
    ports:
      - "8080:80"
    volumes:
      - ./dispatcher/src:/mnt/dev/src:ro
    restart: unless-stopped
    networks: [default]
```

⚠️ **Network alignment:** the current author/publish split (author on `aem-net`, publish on both `aem-net` AND `aem-docker_default`) must include dispatcher. Easiest: connect dispatcher to `aem-net` after `up`:

```bash
docker compose up -d dispatcher
docker network connect aem-net aem-dispatcher
```

Or — the cleaner long-term fix — declare `aem-net` as external in compose and put all services on it.

### Step 5 — Flush agent on author (task #20)

```bash
curl -u admin:admin \
  -F "enabled=true" \
  -F "userId=" \
  -F "transportUri=http://dispatcher:80/dispatcher/invalidate.cache" \
  -F "transportUser=" \
  -F "transportPassword=" \
  http://localhost:4502/etc/replication/agents.author/flush/jcr:content
```

The flush agent is HTTP-based, not durbo. Dispatcher's invalidate endpoint requires no auth but IP-gates via `/cache/allowedClients` in the farm config — our `172.*` allowlist covers the docker bridge.

### Step 6 — Verify (task #21)

```bash
# Bare URL rewrites to SPA
curl -sSI  http://localhost:8080/                                  # 302 → /content/hello.html
curl -sSL  http://localhost:8080/                                  # 200 SPA HTML

# Cache hit on second request (look at timing)
time curl -sS http://localhost:8080/content/hello.html >/dev/null
time curl -sS http://localhost:8080/content/hello.html >/dev/null  # ~10x faster

# Filters block dangerous paths
curl -sSI http://localhost:8080/system/console/bundles             # 404
curl -sSI http://localhost:8080/content/hello.json                 # 404
curl -sSI http://localhost:8080/crx/de                             # 404

# Cache invalidation: edit page title on author, replicate, check dispatcher
# The cache file at dispatcher's /mnt/var/www/html/content/hello.html should be deleted
docker exec aem-dispatcher ls -la /mnt/var/www/html/content/      # before vs after
```

### Step 7 — Swap cloudflared (optional, after verify passes)

```yaml
# ~/.cloudflared/config.yml
- hostname: aem-publish.micstec.com
  service: http://localhost:8080     # was http://localhost:4503
```

```bash
tmux kill-session -t cloudflared
tmux new-session -d -s cloudflared \
  'cloudflared tunnel run minipc2 2>&1 | tee -a ~/micsapp-webterminal/cloudflared.log'
```

## Risk register (things that might bite when we resume)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Adobe `mod_dispatcher.so` ABI mismatch with `httpd:2.4` latest | medium | Pin httpd to version listed in `tools/version.info`; fallback to `httpd:2.4-bookworm` |
| `httpd:2.4` lacks modules dispatcher links against (e.g. mod_proxy_http) | low | Most needed modules are built into stock image; if missing, `apt install` in Dockerfile |
| Adobe's `.sh` extracts to a non-standard layout | low | Inspect first, adjust paths in step 3 |
| Cache invalidation request from publish rejected (403) | medium | `/cache/allowedClients` must list publish container's actual IP — check with `docker inspect aem-publish` |
| Vhost `ServerName` mismatches `Host:` header from cloudflared | medium | Add `*` ServerAlias or explicit hostname; check Apache `access_log` to confirm hostname being received |

## When we resume

User says: *"the dispatcher .sh is at `<path>`, continue"*

Agent action:
1. `TaskList` → confirm tasks 17–21 still pending
2. `TaskUpdate 17 → in_progress`
3. Execute step 1 above (unpack)
4. Iterate through steps 2–7

## Related docs

- `dispatcher.md` — full design + config reference
- `spa_example.md` — what we're protecting with dispatcher
- `aem_docker.md` — author/publish setup
- `cloudflared.md` — public tunnel
