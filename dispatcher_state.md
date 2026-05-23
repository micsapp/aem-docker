# Dispatcher Setup — Final State

Adobe Dispatcher is **deployed and verified end-to-end**: in front of publish, serving the SPA, blocking dangerous paths, caching responses, and being purged on replication.

Last updated: 2026-05-23 (dispatcher upgraded 2.0.269 → 2.0.270 alongside AEM SDK JDK 21 — see `aem_sdk_jdk21.md`)

## Status

| # | Task | Status |
|---|---|---|
| 16 | Write `dispatcher.md` design doc | ✅ done |
| 17 | Obtain dispatcher binary / image | ✅ done — Adobe SDK `.sh`, image loaded |
| 18 | Create `dispatcher/src/` config bundle | ✅ done — Adobe starter + custom rewrite |
| 19 | Add `dispatcher` service to `docker-compose.yml` | ✅ done — YAML committed, not invoked |
| 20 | Configure flush agent on author | ✅ done — replication purges cache |
| 21 | Verify dispatcher serves and caches | ✅ done — all end-to-end checks pass |

## What's running

| Container | Image | Ports | Networks |
|---|---|---|---|
| `aem-author` | (raw quickstart) | 4502, 5005 | aem-net |
| `aem-publish` | (raw quickstart) | 4503, 5006 | aem-net, aem-docker_default |
| `aem-dispatcher` | `adobe/aem-cs/dispatcher-publish:2.0.270` | 8080 → 80 | aem-net (alias `dispatcher`), aem-docker_default |

**Note on launching:** dispatcher is started **standalone via `docker run`**, NOT via `docker compose up`. The compose YAML defines it for reference + use on more powerful machines, but on this host running all three via compose pegs CPU at 100%. See `MEMORY` feedback entry.

## Files in repo

```
aem-docker/
├── docker-compose.yml                              service defs (3 svcs) — DO NOT `compose up` on this host
├── dispatcher/
│   ├── aem-sdk-dispatcher-tools-2.0.270-unix.sh    self-extracting installer (Makeself), 56 MB
│   ├── dispatcher-sdk-2.0.270/                     extracted SDK
│   │   ├── lib/dispatcher-publish-amd64.tar.gz     Docker image tarball (loaded as :2.0.270)
│   │   ├── lib/overwrite_cache_invalidation.sh     Adobe-provided permissive invalidate script
│   │   ├── bin/, src/, docs/                       starter configs + helpers
│   ├── overwrite_cache_invalidation.sh             copy of Adobe script, mounted into entrypoint
│   └── src/                                        our customized config bundle (mounted as /mnt/dev/src)
│       ├── conf.d/rewrites/rewrite.rules           "/" → "/content/spa-mvn.html"
│       ├── conf.d/available_vhosts/default.vhost   from Adobe (env-var driven)
│       ├── conf.d/enabled_vhosts/default.vhost     symlink
│       ├── conf.dispatcher.d/available_farms/default.farm   from Adobe (env-var driven)
│       ├── conf.dispatcher.d/enabled_farms/default.farm     symlink
│       ├── conf.dispatcher.d/filters/, cache/, virtualhosts/, renders/, clientheaders/
│       └── opt-in/USE_SOURCES_DIRECTLY             tells image to use /mnt/dev/src
```

## Launch command (canonical, repeatable)

```bash
docker run -d \
  --name aem-dispatcher \
  -p 8080:80 \
  -v /home/mli/aem-docker/dispatcher/src:/mnt/dev/src:ro \
  -v /home/mli/aem-docker/dispatcher/overwrite_cache_invalidation.sh:/docker_entrypoint.d/45-overwrite-invalidate.sh:ro \
  -e AEM_HOST=publish \
  -e AEM_PORT=4503 \
  -e DISP_LOG_LEVEL=warn \
  -e REWRITE_LOG_LEVEL=warn \
  --restart unless-stopped \
  adobe/aem-cs/dispatcher-publish:2.0.270

docker network connect --alias dispatcher aem-net aem-dispatcher
```

The mounted `45-overwrite-invalidate.sh` runs *after* `40-generate-allowed-clients.sh` and replaces the restrictive default with `/0001 allow *` — needed because author and publish sit on different docker networks, so author's source IP would otherwise be denied.

## Author-side flush agent (one-time config)

```bash
curl -u admin:admin \
  -F "enabled=true" \
  -F "userId=" \
  -F "transportUri=http://dispatcher:80/dispatcher/invalidate.cache" \
  -F "transportUser=" \
  -F "transportPassword=" \
  http://localhost:4502/etc/replication/agents.author/flush/jcr:content
```

Persists across author restarts (stored in JCR at `/etc/replication/agents.author/flush`).

## End-to-end verification (all passed)

| Check | Command | Result |
|---|---|---|
| Bare URL rewrite fires | `curl -I http://localhost:8080/` | 302 → `/content/spa-mvn.html` |
| SPA page renders via dispatcher | `curl -L http://localhost:8080/content/spa-mvn.html` | 200, Vue HTML shell |
| JS clientlib proxied | `curl http://localhost:8080/etc.clientlibs/spa-mvn/clientlibs/clientlib-site.js` | 200, 72 KB |
| CSS clientlib proxied | (...same for .css) | 200, 9.6 KB |
| `/system/console/*` blocked | `curl -I http://localhost:8080/system/console/bundles` | 404 |
| `/crx/de` blocked | `curl -I http://localhost:8080/crx/de` | 404 |
| `*.json` selector blocked | `curl -I http://localhost:8080/content.json` | 404 |
| Cache hit performance | `time curl -o /dev/null http://localhost:8080/content/spa-mvn.html` | 23 ms |
| Author → dispatcher reach | `docker exec aem-author curl -X POST .../invalidate.cache` | 200 |
| **Replication purges cache file** | Activate page → check disk | File deleted from `/mnt/var/www/html/content/spa-mvn/us/en.html` ✓ |

## Operational notes

- **Logs:** `docker exec aem-dispatcher tail -f /var/log/apache2/dispatcher.log` shows hit/miss/blocked.
- **Cache contents:** `docker exec aem-dispatcher find /mnt/var/www/html -type f` shows what's on disk.
- **Manual purge:** `docker exec aem-dispatcher sh -c 'rm -rf /mnt/var/www/html/*'` (or rely on flush agent).
- **Restart dispatcher:** `docker restart aem-dispatcher` — preserves the cache.
- **Reset cache:** `docker exec aem-dispatcher sh -c 'rm -rf /mnt/var/www/html/*'`.

## What's next (optional, not blocking)

- **Cloudflare tunnel swap:** point `aem-publish.micstec.com` at `http://localhost:8080` (dispatcher) instead of `:4503` (publish). One line edit in `~/.cloudflared/config.yml` + tmux session restart.
- **Tighten filters:** the default Adobe filter set is generous (allows `/content/*.html`, `/etc.clientlibs/*`, plus various forms/graphql/screens paths). For a small site, narrowing to just `/content/spa-mvn/*` is reasonable.
- **TLS:** Cloudflare handles HTTPS at the edge; origin stays HTTP. No mod_ssl config needed.

## Related docs

- `dispatcher.md` — design doc / full config reference
- `spa_example.md`, `mvn_spa_dev.md` — what the dispatcher is fronting
- `aem_docker.md`, `cloudflared.md` — surrounding stack
- Memory `feedback-aem-docker-no-compose-up` — why we don't run `docker compose up` on this host
