# AEM Staging Environment — Local AEMaaCS Simulation

How to stand up a second AEM stack on a separate host to mirror the way
AEM as a Cloud Service splits **dev** and **stage** across distinct
infrastructure, and how to promote builds + content from dev → stage.

> **Context:** the existing repo describes a single local AEM stack
> (author + publish + dispatcher) running on the dev workstation —
> see `aem_docker.md`, `aem_sdk_jdk21.md`, `dispatcher_state.md`.
> This doc adds a second physical host running an identical stack as
> **stage**, with a one-way promotion pipeline from dev. Production
> is intentionally *not* simulated locally — see "Why no local prod"
> at the bottom.

## Target topology

```
┌─ dev workstation ─────────────────┐         ┌─ stage host ──────────────────────┐
│  containers on aem-net            │         │  containers on aem-net            │
│    aem-author     :4502           │         │    aem-author     :4502           │
│    aem-publish    :4503           │ ───────►│    aem-publish    :4503           │
│    aem-dispatcher :8080           │ promote │    aem-dispatcher :8080           │
│                                   │         │                                   │
│  source of truth for code         │         │  receives only — never builds     │
│  ./deploy.sh   (build + install)  │         │  no JDK, no Maven, no node here   │
│  ./promote.sh stage   ──────────┐ │         │                                   │
└─────────────────────────────────│─┘         └───────────────────────────────────┘
                                  │
                                  └─ POSTs to http://STAGE_HOST:4502
                                         /crx/packmgr/service.jsp  (package install)
                                         /bin/replicate.json       (activation)
```

**Same image, same compose file, different host.** No code change required
to make `aem-base` and `adobe/aem-cs/dispatcher-publish:2.0.270` run on stage —
they're already environment-agnostic.

## Why this shape

| Decision | Rationale |
|---|---|
| Stage on a separate machine, not a second compose stack on dev | AEMaaCS uses physically separate infra per tier. Co-locating two stacks needs ~15 GB RAM and conflates noisy-neighbor effects. A separate host also forces a real network-mediated promotion pipeline, which is what you'll actually use in production. |
| Only 2 envs (dev + stage), no local prod | Real prod requires Adobe-only features (CDN, Asset Compute, multi-publish failover, IMS). Mocking those locally has diminishing returns. Stage doubles as "prod-like release validation" before you push to a real AEMaaCS prod tier. |
| Stage host never builds | Build artifacts (Maven `*.all-*.zip`) flow *in* from dev. Stage only runs the runtime. This is the same constraint Cloud Manager enforces: stage doesn't have your source tree. |
| Promotion via HTTP, not git | Mirrors Cloud Manager's deploy step — the artifact is the contract, not the source. If `spa-mvn.all-*.zip` installs cleanly on stage, the build is valid. |

## Hardware + software requirements (stage host)

| Resource | Minimum | Why |
|---|---|---|
| OS | Linux x86_64 (Ubuntu 22.04+ ideal) or WSL2 | Same arch as the `aem-base` image we built (`linux/amd64`) |
| RAM | **6 GB free** | Author ~2 GB + Publish ~2 GB + Dispatcher ~100 MB + headroom |
| Disk | **25 GB free** | Quickstart jar 533 MB + 2× `crx-quickstart` (~3 GB each as content grows) + dispatcher SDK ~600 MB + cache |
| CPU | 2 cores | AEM is CPU-bound during boot (~4–8 min cold), idle afterward |
| Required software | `docker` (engine + compose v2), `curl` | Nothing else — no JDK, no Maven, no Node |
| Network ingress | TCP `4502`, `4503`, `8080` reachable from dev's IP | For promotion + verification |

Any of these work: spare laptop, NUC, mini-PC, small VPS (DigitalOcean droplet
4 GB+/2 vCPU works tight; 8 GB/2 vCPU is comfortable), home server.

## Bootstrap the stage machine

### Option A — install-aem.sh from public droppy (one-liner)

The repo's `install_aem.sh` is designed exactly for this. It downloads images
+ quickstart jar + dispatcher config from public droppy share URLs, no Adobe
login, no source checkout needed.

```bash
# on the stage host
curl -fsSL https://tnas_d.micsapp.com/s/install-aem -o install_aem.sh
bash install_aem.sh
```

After ~15 min you have author + publish + dispatcher running.

> ⚠ **Caveat:** the droppy URLs `install_aem.sh` pulls from currently host
> the **older JDK 11 / dispatcher 2.0.269** artifacts. To stage the new
> JDK 21 + dispatcher 2.0.270 stack via this path, re-upload the new
> artifacts to droppy first:
>
> ```bash
> # on the dev host, replace the public shares
> droppy_cli upload aem-sdk/aem-quickstart.jar /public/aem-quickstart-jar/
> droppy_cli upload dispatcher/dispatcher-sdk-2.0.270/lib/dispatcher-publish-amd64.tar.gz /public/aem-dispatcher/
> # then re-run install_aem.sh on stage
> ```
>
> (The aem-base image tarball can be regenerated on stage via
> `docker build -t aem-base .` after cloning the repo — no upload needed.)

### Option B — scp from dev (no droppy involvement)

If droppy isn't available from the stage host, ship artifacts directly:

```bash
# from the dev host
STAGE=user@stage.local

# 1. Clone the repo
ssh "$STAGE" 'git clone https://github.com/micsapp/aem-docker.git ~/aem-docker'

# 2. Ship the proprietary jar (~533 MB)
scp aem-sdk/aem-quickstart.jar "$STAGE:aem-docker/aem-sdk/"

# 3. Ship the dispatcher docker image (~110 MB compressed)
sudo docker save adobe/aem-cs/dispatcher-publish:2.0.270 \
  | ssh "$STAGE" 'sudo docker load'

# 4. Build the aem-base image on stage + start containers
ssh "$STAGE" 'cd aem-docker && sudo docker build -t aem-base .'
ssh "$STAGE" 'cd aem-docker && sudo docker network create aem-net'
ssh "$STAGE" 'cd aem-docker && ./manage-raw.sh start author'   # ~4 min
ssh "$STAGE" 'cd aem-docker && ./manage-raw.sh start publish'  # ~4 min

# 5. Start dispatcher on stage (extract config from repo's dispatcher/src/)
ssh "$STAGE" 'cd aem-docker && sudo docker run -d \
  --name aem-dispatcher --network aem-net --network-alias dispatcher \
  -p 8080:80 \
  -v $PWD/dispatcher/src:/mnt/dev/src:ro \
  -v $PWD/dispatcher/overwrite_cache_invalidation.sh:/docker_entrypoint.d/45-overwrite-invalidate.sh:ro \
  -e AEM_HOST=publish -e AEM_PORT=4503 \
  -e DISP_LOG_LEVEL=warn -e REWRITE_LOG_LEVEL=warn \
  --restart unless-stopped adobe/aem-cs/dispatcher-publish:2.0.270'
```

### Post-bootstrap verification (on stage)

```bash
ssh "$STAGE" 'curl -I http://localhost:4502/libs/granite/core/content/login.html'
ssh "$STAGE" 'curl -I http://localhost:4503/libs/granite/core/content/login.html'
ssh "$STAGE" 'curl -I http://localhost:8080/'
```

All three should return HTTP 200, 200, 302 respectively.

## Network + firewall

Stage needs to accept HTTP from dev's IP (or LAN subnet) on three ports:

```bash
# on the stage host — adjust subnet for your network
sudo ufw allow from 192.168.1.0/24 to any port 4502 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 4503 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 8080 proto tcp
```

If stage is on a different network (cloud VPS, separate office), use one of:

- **SSH tunnel** from dev:
  `ssh -L 14502:localhost:4502 -L 14503:localhost:4503 -L 18080:localhost:8080 stage` — then dev sees stage on `localhost:14502` etc. Simple, no firewall changes, but only works while the tunnel is up.
- **WireGuard / Tailscale VPN** — clean LAN extension, stage looks like a LAN host.
- **Cloudflare Tunnel** — already documented in `cloudflared.md`. Bind `stage-author.<your-domain>` → `http://stage:4502`. Public-internet-facing; lock down with Cloudflare Access policies.

## Stage credentials

**Change `admin/admin` on stage.** Dev can stay default for local convenience;
stage is reachable from at least your dev box and possibly the internet.

```bash
# on stage, via crxde or curl
curl -u admin:admin -F "rep:password=<new-strong-password>" \
  http://localhost:4502/home/users/a/admin.rw.json
```

Then store the new password in your dev host's keychain / `.env` for
`promote.sh` to pick up.

## The promotion pipeline (dev → stage)

This is the new piece — it doesn't exist yet. Add `promote.sh` to the repo root:

```bash
#!/usr/bin/env bash
# promote.sh — push the latest spa-mvn build from dev to a target environment.
#
# Usage: ./promote.sh stage
#
# Env vars (with defaults for "stage"):
#   STAGE_AEM_HOST     host[:port] of stage author       (e.g. 192.168.1.50)
#   STAGE_AEM_PORT     stage author port (default 4502)
#   STAGE_PUBLISH_PORT stage publish port (default 4503)
#   STAGE_DISP_PORT    stage dispatcher port (default 8080)
#   STAGE_AEM_USER     default: admin
#   STAGE_AEM_PASS     required — no default for safety

set -euo pipefail
ENV="${1:?env name required: ./promote.sh stage}"

case "$ENV" in
  stage)
    HOST="${STAGE_AEM_HOST:?set STAGE_AEM_HOST=host or host:port}"
    AUTHOR_PORT="${STAGE_AEM_PORT:-4502}"
    PUB_PORT="${STAGE_PUBLISH_PORT:-4503}"
    DISP_PORT="${STAGE_DISP_PORT:-8080}"
    USER="${STAGE_AEM_USER:-admin}"
    PASS="${STAGE_AEM_PASS:?set STAGE_AEM_PASS=...}"
    ;;
  *) echo "unknown env: $ENV" >&2; exit 1 ;;
esac

AUTHOR_URL="http://${HOST}:${AUTHOR_PORT}"
PUB_URL="http://${HOST}:${PUB_PORT}"
DISP_URL="http://${HOST}:${DISP_PORT}"

# 1. find the latest built all-package on dev
PKG=$(ls -t spa-mvn/all/target/spa-mvn.all-*.zip 2>/dev/null | head -1)
[ -f "$PKG" ] || { echo "no built artifact — run ./spa-mvn/deploy.sh first" >&2; exit 1; }
echo "==> artifact: $PKG"

# 2. reachability check
curl -fsS -o /dev/null -u "$USER:$PASS" "$AUTHOR_URL/libs/granite/core/content/login.html" \
  || { echo "cannot reach $AUTHOR_URL" >&2; exit 2; }

# 3. upload + install to stage author
echo "==> install on $AUTHOR_URL"
curl -fsS -u "$USER:$PASS" \
  -F "file=@$PKG" -F "name=spa-mvn.all" -F "force=true" -F "install=true" \
  "$AUTHOR_URL/crx/packmgr/service.jsp" | grep -E '<status code|Package installed' | head

# 4. install on stage publish too (autoInstallPackage targets author only)
echo "==> install on $PUB_URL (publish)"
curl -fsS -u "$USER:$PASS" \
  -F "file=@$PKG" -F "name=spa-mvn.all" -F "force=true" -F "install=true" \
  "$PUB_URL/crx/packmgr/service.jsp" | grep -E '<status code|Package installed' | head

sleep 10

# 5. activate content from author -> publish (within stage)
for p in /content/spa-mvn /content/spa-mvn/us /content/spa-mvn/us/en \
         /content/dam/spa-mvn /content/dam/spa-mvn/cf \
         /content/dam/spa-mvn/cf/hero /content/dam/spa-mvn/cf/cta_banner \
         /content/dam/spa-mvn/cf/features /content/dam/spa-mvn/cf/stats; do
  curl -fsS -u "$USER:$PASS" -X POST \
    -F "path=$p" -F "cmd=Activate" -F "deep=true" \
    "$AUTHOR_URL/bin/replicate.json" -o /dev/null \
    -w "  activate $p -> %{http_code}\n"
done

# 6. verify end-to-end
sleep 5
echo "==> verify"
curl -fsS -o /dev/null -w "  $PUB_URL/content/spa-mvn/us/en.html -> %{http_code}\n" \
  "$PUB_URL/content/spa-mvn/us/en.html"
curl -fsS -o /dev/null -L -w "  $DISP_URL/  -> %{http_code} (%{url_effective})\n" \
  "$DISP_URL/"
echo "==> done"
```

Usage:

```bash
# one-time: configure stage target in your shell
export STAGE_AEM_HOST=192.168.1.50
export STAGE_AEM_PASS=<your-stage-admin-pwd>

# build (dev) then promote
./spa-mvn/deploy.sh
./promote.sh stage
```

### What promote.sh deliberately does NOT do

- **Doesn't replicate `/apps` or `/conf` from dev author to stage author.**
  Code (bundles, components, templates) lands on stage via the `all` package
  install in step 3. Replication is reserved for **content** that authors
  produce on dev and want to ship to stage.
- **Doesn't run tests.** Add a `--with-tests` flag later if you want a
  Cloud-Manager-style quality gate.
- **Doesn't roll back.** If install fails on stage, the JCR snapshot AEM
  takes pre-install can be restored from the package manager UI on stage.
- **Doesn't promote stage → prod.** Real prod is AEMaaCS — use Cloud
  Manager's pipeline for that step.

## Environment-specific OSGi configs

The same all-package deploys to both envs, so any difference (log levels,
external service URLs, CORS origins, dispatcher tuning) has to live in
runmode-scoped OSGi configs inside `ui.config`. Pattern:

```
spa-mvn/ui.config/src/main/content/jcr_root/apps/spa-mvn/osgiconfig/
├── config/                       # applies to all envs + all instances
├── config.author/                # applies to all envs, author only
├── config.publish/               # applies to all envs, publish only
├── config.author.dev/            # dev-only (runmode "dev")  -- author
├── config.publish.dev/           # dev-only, publish
├── config.author.stage/          # stage-only, author
└── config.publish.stage/         # stage-only, publish
```

The author + publish containers already start with runmode `dev` baked in
(`AEM_RUNMODE=author,nosamplecontent` etc — `dev` should be appended
explicitly). For stage, the entrypoint env var becomes
`AEM_RUNMODE=author,nosamplecontent,stage` on stage's containers — change
this in stage's `manage-raw.sh` invocation or via a stage-specific compose
file.

Concrete example — different CORS allowlist per env:

```
config.author.dev/com.adobe.granite.cors.impl.CORSPolicyImpl~spa.cfg.json
  { "alloworigin": ["http://localhost:5173"] }    # Vite dev server

config.author.stage/com.adobe.granite.cors.impl.CORSPolicyImpl~spa.cfg.json
  { "alloworigin": ["https://stage-spa.example.com"] }
```

## Operational concerns

| Concern | Recommendation |
|---|---|
| **Backups** | Stage is a release-validation env, not source-of-truth. Restoring from a fresh `promote.sh` run is the recovery path. Snapshot `aem-author/crx-quickstart` weekly if you want point-in-time restore. |
| **Monitoring** | At minimum, `curl /libs/granite/core/content/login.html` from a cron on dev — alert if not 200. For more, install `node-exporter` + `cadvisor` on stage and scrape from dev's Prometheus. |
| **Log access** | `ssh stage 'docker logs -f aem-author'` or expose logs over Promtail → Loki if you have a central log stack. |
| **Updates** | When dev upgrades AEM SDK or dispatcher, rebuild stage the same way: scp the new jar + image, restart containers. Or re-run `install_aem.sh` if droppy URLs are updated. |
| **Tear-down / reset** | `ssh stage 'docker rm -f aem-author aem-publish aem-dispatcher && rm -rf aem-author/crx-quickstart aem-publish/crx-quickstart'` then re-run the bootstrap. ~10 min to a clean stage. |

## Why no local prod

Production in real AEMaaCS depends on:

- **Adobe-managed CDN** (Cloudflare wrapper with edge caching) — no local equivalent
- **Multi-publish replicas behind a load balancer** — could be simulated but adds complexity for no testing benefit
- **Asset Compute Service** (cloud image processing) — proprietary, cloud-only
- **IMS authentication, Adobe Analytics integration, Adobe Target** — IMS-gated
- **24/7 monitoring + on-call** — you don't want this on a laptop

Trying to mock these locally is high-effort, low-fidelity. Better to:
1. Use **stage** as your "prod-like release validation" — same image, same code path, real network promotion.
2. When ready for actual prod, push to a **real AEMaaCS prod tier** via Cloud Manager.
3. Treat the gap between stage and prod as an integration test against the real cloud — Adobe's prod environment is the source of truth for prod behavior, not a local mock.

## Future improvements (not in scope of initial setup)

- **`manage-stage.sh`** wrapper using `DOCKER_HOST=ssh://stage` so stage's
  containers can be started/stopped from the dev terminal without SSHing in.
- **CI/CD on push** — GitHub Action that builds `spa-mvn` on every push to
  main, scp's the artifact to stage, runs `promote.sh stage` automatically.
- **Cypress smoke tests** run against stage after every promotion.
- **Stage-only dispatcher tuning** — longer cache TTLs, stricter filters, to
  match prod-like behavior more closely.
- **Read-only stage** — disable replication agent on stage's author, so the
  only way content gets there is via `promote.sh`. Mirrors AEMaaCS prod
  immutability.

## Related docs

- `aem_docker.md` — single-stack architecture (dev baseline)
- `aem_sdk_jdk21.md` — runtime stack upgrade history (JDK 21 + dispatcher 2.0.270)
- `dispatcher_state.md` — dispatcher container, configs, verification table
- `mvn_spa_dev.md` — Maven build pipeline + container build path
- `cloudflared.md` — exposing local AEM via Cloudflare Tunnel (applies to stage too)
- `install_aem.sh` — public-droppy bootstrap script (works on stage as-is once droppy URLs are refreshed)
