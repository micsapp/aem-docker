# AEM SDK Upgrade — JDK 21

Upgrade the local AEM-as-a-Cloud-Service stack to the latest SDK
(`aem-sdk-2026.5.25892.20260506T135241Z-260400`), which requires **JDK 21**.

Last updated: 2026-05-23

## Summary of the change

| Component | Before | After |
|---|---|---|
| AEM quickstart jar | `aem-sdk-quickstart-2024.4.15977.20240418T174835Z-240300.jar` (Java 11) | `aem-sdk-quickstart-2026.5.25892.20260506T135241Z-260400.jar` (Java 21) |
| Base Docker image | `eclipse-temurin:11-jdk-jammy` | `eclipse-temurin:21-jdk-jammy` |
| Dispatcher tools | `aem-sdk-dispatcher-tools-2.0.269.1-unix.sh` | `aem-sdk-dispatcher-tools-2.0.270-unix.sh` (bundled in the SDK zip) |
| Dispatcher Docker image | `adobe/aem-cs/dispatcher-publish:2.0.269` | `adobe/aem-cs/dispatcher-publish:2.0.270` |

### About the dispatcher (applied)

The SDK zip bundles **`aem-sdk-dispatcher-tools-2.0.270`** — newer than the
standalone `beta-2.0.269.1` also sitting on droppy. The host was clean (no
prior dispatcher container), so the upgrade was done in one pass:

1. Ran `dispatcher/aem-sdk-dispatcher-tools-2.0.270-unix.sh --noexec --keep`
   to extract `dispatcher/dispatcher-sdk-2.0.270/`.
2. `docker load -i dispatcher-sdk-2.0.270/lib/dispatcher-publish-amd64.tar.gz`
   → loaded `adobe/aem-cs/dispatcher-publish:2.0.270` (114 MB).
3. Diffed `src/` against the new SDK template. Only `conf.d/dispatcher_vhost.conf`
   had an upstream change (GraphQL `RewriteCond`/`RewriteEngine Off` cruft
   removed in `.270`). Adopted the new template. `rewrite.rules` and
   `filters.any` are pure user-additions (SPA root redirect + DAM CF allow) —
   left untouched.
4. `bin/validator full -relaxed src` → `No issues found` (single optional
   `ignoreUrlParameters` warning, not a regression).
5. Bumped `docker-compose.yml` and `install_aem.sh` from `:2.0.269` to `:2.0.270`.
6. Bumped `dispatcher_state.md` to reflect the new version + new SDK directory
   name + the new installer filename.
7. Started `aem-dispatcher` under the new image. Container sits at
   `30-wait-for-backend.sh` because publish isn't running — expected, not an error.
   Apache will come up automatically once publish is reachable.

## Artifact sources on droppy

```
/aem_jdk21/aem-sdk-2026.5.25892.20260506T135241Z-260400.zip          (558 MB)
/aem_jdk21/aem-sdk-dispatcher-tools-beta-2.0.269.1-unix.sh           (423 MB) — older, not used
```

Fetch with:

```bash
droppy_cli download /aem_jdk21/aem-sdk-2026.5.25892.20260506T135241Z-260400.zip \
  /tmp/aem-sdk-jdk21.zip
```

The SDK zip ships three top-level files:

```
aem-sdk-quickstart-2026.5.25892.20260506T135241Z-260400.jar   (453 MB)  -> aem-sdk/aem-quickstart.jar
aem-sdk-dispatcher-tools-2.0.270-unix.sh                       ( 56 MB) -> dispatcher/ (staged, not run)
aem-sdk-dispatcher-tools-2.0.270-windows.zip                   ( 25 MB) — ignored on Linux
```

## Implementation steps

1. **Download** the SDK zip from droppy to `/tmp/aem-sdk-jdk21.zip`.
2. **Extract** only the inner `aem-sdk-quickstart-*.jar` to
   `aem-sdk/aem-quickstart.jar` (overwriting the old one). The zip also contains
   the dispatcher tools `.sh` — skip it; we keep the existing dispatcher.
3. **Edit `Dockerfile`** — change `FROM eclipse-temurin:11-jdk-jammy` to
   `FROM eclipse-temurin:21-jdk-jammy`.
4. **Rebuild** the base image:
   ```bash
   docker build -t aem-base .
   ```
5. **Smoke-test** the author container under JDK 21:
   ```bash
   ./manage-raw.sh delete author
   ./manage-raw.sh start  author
   docker logs -f aem-author     # expect "Quickstart started"
   curl -I http://localhost:4502/libs/granite/core/content/login.html   # expect 200
   ```
6. **Doc updates** — every "Java 11 / JDK 11 / eclipse-temurin:11" reference in
   the runtime docs is updated to JDK 21:
   - `README.md` — base-image section, troubleshooting block
   - `aem_docker.md` — architecture section, dir-structure comment
   - `aem-sdk/README.md` — filename example bumped to the new SDK
   - This file (`aem_sdk_jdk21.md`)

   *Out of scope:* `mvn_spa_dev.md` and `spa_example.md` document the Maven
   build host environment (still JDK 11 on the user's box). If/when the spa
   project is rebuilt against the new SDK, those docs should be revisited
   separately — that's a build-toolchain concern, not an SDK-runtime concern.

## Files changed

```
Dockerfile                — JDK 11 → JDK 21
aem-sdk/aem-quickstart.jar  (binary swap)
aem-sdk/README.md         — filename example bumped
README.md                 — Java 11 → Java 21 references
aem_docker.md             — Java 11 → Java 21 references
aem_sdk_jdk21.md          — this plan + status doc (new)
```

## Files intentionally NOT changed

- `docker-compose.yml` — dispatcher image `2.0.269` still valid; per
  `dispatcher_state.md` we don't `compose up` on this host anyway.
- `entrypoint.sh` — works identically under JDK 21 (the `-agentlib:jdwp`
  address syntax is already Java 9+ compatible).
- `install_aem.sh` — the public droppy share URLs it pulls from
  (`URL_QUICKSTART_JAR`, `URL_AEM_IMAGES`) point at *separately uploaded*
  share artifacts. Re-uploading those to droppy is operator work and out of
  scope for this local upgrade.
- `dispatcher/` — version-locked at 2.0.269.1, identical to droppy's beta.

## Rollback

```bash
# Restore old jar (if you kept it)
mv aem-sdk/aem-quickstart.jar.jdk21 aem-sdk/aem-quickstart.jar.bak
mv aem-sdk/aem-quickstart.jar.jdk11 aem-sdk/aem-quickstart.jar

# Revert Dockerfile
sed -i 's/eclipse-temurin:21-jdk-jammy/eclipse-temurin:11-jdk-jammy/' Dockerfile

docker build -t aem-base .
./manage-raw.sh delete author && ./manage-raw.sh start author
```

The `crx-quickstart/` repository data created under JDK 11 is **not**
guaranteed to be readable by an SDK that expects JDK 21 + a new Oak schema.
If the author fails to start after the upgrade, the safe path is a hard
reset of the repository:

```bash
docker rm -f aem-author aem-publish
rm -rf aem-author/crx-quickstart aem-publish/crx-quickstart
./manage-raw.sh start author
```

## Upgrading a host with prior 2024-era data in `crx-quickstart`

**The trap:** swapping the jar + rebuilding the Docker image is **not enough**
when the host already has a `crx-quickstart/` directory from a prior 2024.x
SDK boot. AEM's launchpad — the actual bundle code it runs — is extracted
from the original jar into `crx-quickstart/launchpad/felix/` on first boot,
and is *never* re-extracted on subsequent boots. The mounted jar at
`/opt/aem/aem-quickstart.jar` becomes mostly a fingerprint reference; the
running code is whatever launched first.

Symptom: `/system/console/productinfo` still reports
`Adobe Experience Manager (2024.4.15977.20240418T174835Z)` even after the
container is running on the new JDK 21 image with the 2026 jar mounted in.

**This was hit on minipc2** (the second host we aligned to this stack on
2026-05-24). The Dockerfile/jar/dispatcher were all updated and containers
recreated, but author and publish kept reporting 2024.4. Adobe's documented
local-dev upgrade path is to start fresh — there is no in-place SDK version
migration for the Cloud Service SDK.

### The wipe-and-rebootstrap procedure

```bash
# from the host being upgraded (e.g. minipc2)
cd ~/aem-docker

# 1. stop everything (preserve nothing in crx-quickstart)
sudo docker stop aem-author aem-publish aem-dispatcher

# 2. wipe both AEM repos. Parent dirs are root-owned because the
#    container ran as root and wrote there.
sudo rm -rf aem-author/crx-quickstart aem-publish/crx-quickstart
sudo mkdir -p aem-author/crx-quickstart aem-publish/crx-quickstart
sudo chown -R "$(id -u):$(id -g)" aem-author aem-publish

# 3. recreate the containers, NOT just restart them.
#    Docker Desktop's WSL bind-mount cache locks the path of a
#    deleted+recreated dir to its old inode — a stopped container
#    will refuse to start with "mount src=... no such file or directory".
#    `docker rm` + fresh `docker run` is mandatory.
sudo docker rm -f aem-author aem-publish

# 4. SEQUENTIAL bootstrap (critical on RAM-constrained hosts, 8 GB or less).
#    Booting both AEM JVMs at once during the SDK unpack phase will
#    swap-thrash and stall the box. Start author, wait for HTTP 200 on
#    /libs/granite/core/content/login.html (~3-5 min), THEN start publish.
sudo docker run -d --name aem-author --network aem-net --network-alias author \
  -p 4502:4502 -p 5005:5005 \
  -e AEM_RUNMODE=author,nosamplecontent -e AEM_PORT=4502 -e AEM_DEBUG=false \
  -e JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m" \
  -v "$PWD/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
  -v "$PWD/aem-author/crx-quickstart:/opt/aem/crx-quickstart" \
  --restart unless-stopped aem-base

# poll until author ready, then:
sudo docker run -d --name aem-publish --network aem-net --network-alias publish \
  -p 4503:4503 -p 5006:5005 \
  -e AEM_RUNMODE=publish -e AEM_PORT=4503 -e AEM_DEBUG=false \
  -e JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m" \
  -v "$PWD/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
  -v "$PWD/aem-publish/crx-quickstart:/opt/aem/crx-quickstart" \
  --restart unless-stopped aem-base

# 5. dispatcher (cheap, restart-only is fine since no version-pinned data)
sudo docker start aem-dispatcher
```

Verification that the upgrade is real:

```bash
curl -s -u admin:admin "http://localhost:4502/system/console/productinfo" \
  | grep -oE 'Adobe Experience Manager[^<]*\([0-9.TZ-]+\)'
# Expected: Adobe Experience Manager (2026.5.25892.20260506T135241Z)
```

### Post-wipe: rebuild the world

A fresh `crx-quickstart` means **all** project content is gone: SPA pages,
content fragments, OSGi configs the project shipped, replication agents,
admin password customizations. Reapply in this order:

1. Build + install the all-package (autoInstallPackage targets author only):
   ```bash
   ./spa-mvn/deploy.sh --clean
   ```
2. Install the same package on publish (publish doesn't get autoInstall):
   ```bash
   curl -u admin:admin -F "file=@spa-mvn/all/target/spa-mvn.all-0.0.1-SNAPSHOT.zip" \
        -F "name=spa-mvn.all" -F "force=true" -F "install=true" \
        http://localhost:4503/crx/packmgr/service.jsp
   ```
3. Configure the `publish` replication agent with the right `userId` and
   transportUri — the AEM default is the placeholder `your_replication_user`
   which silently fails. See "Gotchas hit and fixed" below.
4. Configure the dispatcher `flush` agent.
5. Activate the content tree (`/apps/spa-mvn`, `/etc/clientlibs/spa-mvn`,
   `/conf/spa-mvn`, `/content/spa-mvn`, `/content/dam/spa-mvn`) from author
   to publish. Use `cmd=Activate&deep=true` to recurse.
6. If you had Content Fragments authored manually, restore them from a
   package backup taken before the wipe (see `aem_stg.md` option C for the
   `querybuilder` + `packmgr` backup recipe) or recreate them.

### When you can skip this whole section

This procedure is only needed when the upgrade-target host has a
**non-empty** `aem-{author,publish}/crx-quickstart/` from a previous SDK
version. On a fresh host where `crx-quickstart/` doesn't exist yet (or is
empty), the first boot of the new image with the new jar bootstraps cleanly
and `productinfo` correctly reports the new version. That's the path
described at the top of this doc and used for this stack's own initial
setup. The wipe procedure is the recovery path for when in-place jar swap
"looks done but isn't."

## Status

| Step | State |
|---|---|
| 1. Download SDK zip from droppy | ✅ done — `/tmp/aem-sdk-jdk21.zip` (533 MB on disk) |
| 2. Extract quickstart jar | ✅ done — `aem-sdk/aem-quickstart.jar` (453 MB) |
| 3. Dockerfile → JDK 21 | ✅ done |
| 4. Doc updates (README, aem_docker, aem-sdk/README) | ✅ done |
| 5. Stage new dispatcher SDK (2.0.270) | ✅ done — installer at `dispatcher/aem-sdk-dispatcher-tools-2.0.270-unix.sh`, not executed |
| 6. Rebuild base image | ✅ done — `aem-base:latest`, `openjdk version "21.0.11" Temurin-21.0.11+10` |
| 7. Smoke-test author boot under JDK 21 | ✅ done — `aem-author` running, login.html → 200 after ~4 min |
| 8. Dispatcher upgrade to 2.0.270 | ✅ done — image loaded, configs validated, container running on `:8080` |
| 9. Configure publish replication agent | ✅ done — `userId=admin`, `transportUri=http://publish:4503/bin/receive?sling:authRequestLogin=1` |
| 10. Configure dispatcher flush agent | ✅ done — `transportUri=http://dispatcher:80/dispatcher/invalidate.cache`, ACTIVATE fires on every replication |
| 11. Build + install SPA (autoInstallPackage on author) | ✅ done — 10/10 modules, ~4 min in `maven:3.9-eclipse-temurin-21` container |
| 12. Install all-package on publish | ✅ done — uploaded `spa-mvn.all-0.0.1-SNAPSHOT.zip` via package manager service.jsp |
| 13. End-to-end verification (dispatcher → publish, blocked paths, clientlibs, cache, flush) | ✅ done — full matrix in section below |

### Gotchas hit and fixed

- **Default `publish` agent `userId` was the placeholder `your_replication_user`** — replication failed silently with `Unable to build content for agent 'publish'. Invalid userId`. Fixed by POSTing `userId=admin` to `/etc/replication/agents.author/publish/jcr:content`. The `manage-raw.sh connect` function in this repo doesn't set `userId`, so any future fresh-author run will hit this.
- **`/bin/replicate.json` requires `cmd=Activate`, not `action=Activate`** — wrong param returns 403 "No rights to replicate".
- **`autoInstallPackage` only installs to author** — publish needs the `all` package uploaded separately via `/crx/packmgr/service.jsp` (or a deep tree-activation from author once bundles are in `/apps/<project>/install`).
- **`treeactivation.html` doesn't actually walk the tree.** It only queues the root path. Must enumerate children via querybuilder and POST each, OR install the all-package directly on publish.
- **Maven build needs the `--network host` flag in the docker run** to reach `localhost:4502` (since `autoInstallPackage` posts the built zip back to AEM).

### End-to-end verification matrix (2026-05-23 22:13 UTC)

```
dispatcher /  -> 302                                            302 (0B)        OK
dispatcher / -L final  -> /content/spa-mvn/us/en.html           200 (627B)      OK
dispatcher clientlib JS                                         200 (73898B)    OK
dispatcher clientlib CSS                                        200 (10507B)    OK
dispatcher /system/console/bundles BLOCKED                      404             OK
dispatcher /crx/de BLOCKED                                      404             OK
dispatcher /content.json BLOCKED                                404             OK
publish anon /content/spa-mvn/us/en.html                        200 (627B)      OK
publish anon /content/dam/spa-mvn/asset.jpg                     200 (71150B)    OK
author admin /content/spa-mvn/us/en.html                        200 (836B)      OK

cold cache: 1.97 ms     warm cache: 1.61 ms
cache files: /mnt/var/www/html/content/spa-mvn/us/en.html  +  en.html.h
flush agent fires `Agent.flush Replication (ACTIVATE) ... successful` on every activate.
```

(This checkout had no prior `aem-author/crx-quickstart/` or
`aem-publish/crx-quickstart/` data, so first boot initialized cleanly under
JDK 21 with no Oak-schema migration risk.)

## Verified runtime

```text
Image:        aem-base:latest                          (FROM eclipse-temurin:21-jdk-jammy)
Container:    aem-author                               (ports 4502, 5005)
Java:         openjdk 21.0.11 Temurin-21.0.11+10
SDK jar:      aem-sdk-quickstart-2026.5.25892.20260506T135241Z-260400.jar (453 MB)
Run modes:    s7connect, crx3, nosamplecontent, author, sdk, live, crx3tar
First-boot:   ~4 min from container create → HTTP 200 on /libs/granite/core/content/login.html

Image:        adobe/aem-cs/dispatcher-publish:2.0.270  (114 MB)
Container:    aem-dispatcher                            (port 8080 → 80)
Apache:       Apache/2.4.66 (Unix) OpenSSL/3.5.5 Communique/4.3.8-20260309 mod_qos/11.73
Status:       Up, httpd serving — rewrite fires "/" → /content/spa-mvn.html and proxies to publish:4503
Validator:    cloud-manager validator 2.0.89 — No issues found (single optional ignoreUrlParameters warning)

Image:        aem-base:latest                          (JDK 21)
Container:    aem-publish                               (ports 4503, 5006)
First-boot:   ~4 min from container create → HTTP 200 on /libs/granite/core/content/login.html
```

## Operator commands (reference)

```bash
# from /home/mli/aem-docker
sudo docker build -t aem-base .                              # rebuild JDK 21 image
sudo docker network inspect aem-net >/dev/null 2>&1 || sudo docker network create aem-net
sudo docker rm -f aem-author 2>/dev/null || true
sudo docker run -d --name aem-author --network aem-net --network-alias author \
  -p 4502:4502 -p 5005:5005 \
  -e AEM_RUNMODE=author,nosamplecontent -e AEM_PORT=4502 -e AEM_DEBUG=false \
  -e JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m" \
  -v "$PWD/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
  -v "$PWD/aem-author/crx-quickstart:/opt/aem/crx-quickstart" \
  --restart unless-stopped aem-base
sudo docker logs -f aem-author                               # watch first boot
curl -I http://localhost:4502/libs/granite/core/content/login.html   # expect 200
```

> Note: the user `mli` is **not** in the `docker` group on this host, so
> `manage-raw.sh` (which calls `docker` directly) only works after either
> adding `mli` to `docker` and re-logging in, or running it via `sudo`.
