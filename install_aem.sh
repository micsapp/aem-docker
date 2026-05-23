#!/usr/bin/env bash
# install_aem.sh — bring up the full AEM stack (author + publish + dispatcher)
# from public droppy share URLs, ONE container at a time.
#
# Author boot alone uses ~2 GB RAM and pegs CPU for several minutes; starting
# multiple AEM JVMs simultaneously spikes the host to 100% and stalls every
# container. This script enforces strict sequencing:
#
#     load images → create network → author (wait ready) → publish (wait ready) → dispatcher
#
# Self-contained: only requires docker + curl. Pulls artifacts from public
# droppy share links — no droppy_cli, no Adobe SD login, no Maven build needed.
#
# Idempotent: re-running skips work that's already done. Safe to run on a
# partially-set-up host.

set -euo pipefail

# ----- defaults / public share URLs -----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# When invoked from `curl | bash` (no script file) we still need a working dir.
# Fall back to the user's CWD in that case so artifacts land somewhere sensible.
[ -f "${BASH_SOURCE[0]:-}" ] || SCRIPT_DIR="${AEM_DOCKER_HOME:-$PWD/aem-docker}"
REPO_DIR="${AEM_DOCKER_HOME:-$SCRIPT_DIR}"

IMG_DIR="${REPO_DIR}/.image-cache"

# Public download URLs (no auth required)
URL_AEM_IMAGES="https://tnas_d.micsapp.com/s/aem-images"
URL_DISP_IMAGE="https://tnas_d.micsapp.com/s/aem-dispatcher"
URL_QUICKSTART_JAR="https://tnas_d.micsapp.com/s/aem-quickstart-jar"
URL_INSTALL_SCRIPT="https://tnas_d.micsapp.com/s/install-aem"

# Image tags we expect after loading
AEM_IMAGE="aem-base:latest"
DISP_IMAGE="adobe/aem-cs/dispatcher-publish:2.0.270"

# Container names + ports
AUTHOR_NAME="aem-author"
PUBLISH_NAME="aem-publish"
DISP_NAME="aem-dispatcher"

AUTHOR_PORT=4502
PUBLISH_PORT=4503
DISP_PORT=8080
DEBUG_AUTHOR_PORT=5005
DEBUG_PUBLISH_PORT=5006

NETWORK="aem-net"
JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m"

# Boot readiness timeout per AEM container (seconds)
AEM_READY_TIMEOUT="${AEM_READY_TIMEOUT:-900}"   # 15 min
AEM_READY_POLL="${AEM_READY_POLL:-15}"

# ----- pretty output ---------------------------------------------------------
c_grey()  { printf '\033[90m%s\033[0m' "$*"; }
c_blue()  { printf '\033[34m%s\033[0m' "$*"; }
c_green() { printf '\033[32m%s\033[0m' "$*"; }
c_yel()   { printf '\033[33m%s\033[0m' "$*"; }
c_red()   { printf '\033[31m%s\033[0m' "$*"; }
c_bold()  { printf '\033[1m%s\033[0m' "$*"; }

log()  { printf '%s %s\n' "$(c_grey "[$(date +%H:%M:%S)]")" "$*"; }
step() { printf '\n%s %s\n' "$(c_blue '==>')" "$(c_bold "$*")"; }
ok()   { printf '   %s %s\n' "$(c_green ok)" "$*"; }
warn() { printf '   %s %s\n' "$(c_yel WARN)" "$*"; }
die()  { printf '\n%s %s\n' "$(c_red 'ERROR')" "$*" >&2; exit 1; }

# ----- usage -----------------------------------------------------------------
usage() {
  cat <<EOF
$(c_bold "install_aem.sh") — bootstrap an AEM (author + publish + dispatcher) stack
                  on any Linux host with docker + curl.

USAGE
    ./install_aem.sh              # default: download artifacts, load, start all sequentially
    ./install_aem.sh --recreate   # tear down existing containers first
    ./install_aem.sh --no-publish # skip publish + dispatcher (author only)
    ./install_aem.sh --no-dispatcher  # skip dispatcher
    ./install_aem.sh --status     # just print current state

ONE-LINER from a fresh host:
    curl -fsSL $URL_INSTALL_SCRIPT -o install_aem.sh && bash install_aem.sh

FLOW (always strictly sequential, never parallel)
    1.  preflight: docker, curl
    2.  download + load image tarballs (skip if image present)
    3.  download aem-quickstart.jar (skip if present)
    4.  download dispatcher config bundle (skip if present)
    5.  create docker network ($NETWORK) if missing
    6.  start $AUTHOR_NAME  -> wait until 4502 returns HTTP 200
    7.  start $PUBLISH_NAME -> wait until 4503 returns HTTP 200
    8.  start $DISP_NAME    -> Apache + dispatcher in front of publish
    9.  print summary + URLs

WHY SEQUENTIAL
    Each AEM JVM holds ~2 GB heap and pegs CPU for ~5 minutes at boot.
    Launching all three together stalls the host and often leaves containers
    in a half-up state. Booting one at a time is reliable on modest hardware.

ENV VARS
    AEM_DOCKER_HOME=$REPO_DIR    where to put artifacts + crx-quickstart data
    AEM_READY_TIMEOUT=$AEM_READY_TIMEOUT     per-container boot timeout (s)
    AEM_READY_POLL=$AEM_READY_POLL           poll interval (s)

DOWNLOAD SIZE
    ~600 MB total: 182 MB AEM images + 21 MB dispatcher image + 400 MB quickstart jar
    All cached under $IMG_DIR — second run skips downloads.
EOF
}

# ----- arg parsing -----------------------------------------------------------
RECREATE=0
SKIP_PUBLISH=0
SKIP_DISPATCHER=0
JUST_STATUS=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --recreate)       RECREATE=1 ;;
    --no-publish)     SKIP_PUBLISH=1 ; SKIP_DISPATCHER=1 ;;
    --no-dispatcher)  SKIP_DISPATCHER=1 ;;
    --status)         JUST_STATUS=1 ;;
    --help|-h)        usage; exit 0 ;;
    *)                die "unknown arg: $1   (try --help)" ;;
  esac
  shift
done

# ----- status mode -----------------------------------------------------------
status_print() {
  step "Stack state"
  printf '   %-22s %-22s %s\n' 'CONTAINER' 'STATUS' 'PORTS'
  for c in $AUTHOR_NAME $PUBLISH_NAME $DISP_NAME; do
    s=$(docker ps -a --filter "name=^${c}$" --format '{{.Status}}' 2>/dev/null || true)
    p=$(docker ps -a --filter "name=^${c}$" --format '{{.Ports}}' 2>/dev/null || true)
    printf '   %-22s %-22s %s\n' "$c" "${s:-not present}" "${p:-}"
  done
  echo
  if docker network inspect $NETWORK >/dev/null 2>&1; then
    ok "network $NETWORK exists"
    docker network inspect $NETWORK -f '{{range $c, $v := .Containers}}     attached: {{$v.Name}}  ({{$v.IPv4Address}}){{println ""}}{{end}}' | grep -v '^$' || true
  else
    warn "network $NETWORK does not exist"
  fi
}

if [ "$JUST_STATUS" = "1" ]; then
  status_print
  exit 0
fi

# ----- preflight -------------------------------------------------------------
step "Preflight"
command -v docker >/dev/null || die "docker not on PATH — install Docker first (https://docs.docker.com/get-docker/)"
command -v curl   >/dev/null || die "curl not on PATH — install curl first"

docker info >/dev/null 2>&1 || die "docker daemon not reachable — start Docker Desktop / dockerd"
ok "docker + curl present, daemon reachable"

mkdir -p "$IMG_DIR" "$REPO_DIR/aem-sdk" "$REPO_DIR/aem-author/crx-quickstart" "$REPO_DIR/aem-publish/crx-quickstart" \
         "$REPO_DIR/dispatcher"

# ----- download helper -------------------------------------------------------
download() {
  local url="$1" dest="$2"
  local label
  label="$(basename "$dest") ($(numfmt --to=iec --suffix=B $(curl -sSI -L "$url" | grep -i '^content-length' | tail -1 | awk '{gsub(/\r/,""); print $2}') 2>/dev/null || echo "?"))"
  log "downloading $label"
  curl -fsSL "$url" -o "$dest.part" --progress-bar
  mv "$dest.part" "$dest"
}

# ----- 1) ensure images loaded ----------------------------------------------
step "Images"

have_image() { docker image inspect "$1" >/dev/null 2>&1; }

ensure_image() {
  local image="$1" url="$2" local_name="$3"
  if have_image "$image"; then ok "$image already loaded"; return 0; fi
  local tarball="${IMG_DIR}/${local_name}"
  [ -f "$tarball" ] || download "$url" "$tarball"
  log "docker load < $local_name"
  docker load -i "$tarball" >/dev/null
  have_image "$image" || die "after load, $image still missing"
  ok "$image loaded"
}

ensure_image "$AEM_IMAGE"  "$URL_AEM_IMAGES" "aem-images.tar.gz"
ensure_image "$DISP_IMAGE" "$URL_DISP_IMAGE" "adobe-dispatcher.tar.gz"

# ----- 2) ensure quickstart.jar present -------------------------------------
step "AEM quickstart.jar"

JAR_PATH="$REPO_DIR/aem-sdk/aem-quickstart.jar"
if [ -f "$JAR_PATH" ]; then
  ok "quickstart present ($(du -h "$JAR_PATH" | cut -f1))"
else
  download "$URL_QUICKSTART_JAR" "$JAR_PATH"
  ok "quickstart downloaded"
fi

# ----- 3) ensure dispatcher config bundle present ---------------------------
step "Dispatcher config bundle"

DISP_SRC="$REPO_DIR/dispatcher/src"
DISP_INVALIDATE="$REPO_DIR/dispatcher/overwrite_cache_invalidation.sh"

if [ -d "$DISP_SRC" ] && [ -f "$DISP_INVALIDATE" ]; then
  ok "dispatcher config already present at $DISP_SRC"
else
  warn "dispatcher config bundle not found at $REPO_DIR/dispatcher/"
  warn "the dispatcher container needs custom config files (vhost rewrite,"
  warn "filter rules, cache invalidate overwrite). Clone the full repo:"
  warn "  git clone https://github.com/micsapp/aem-docker.git $REPO_DIR"
  if [ "$SKIP_DISPATCHER" != "1" ]; then
    warn "skipping dispatcher (run with --no-dispatcher to suppress)"
    SKIP_DISPATCHER=1
  fi
fi

# ----- 4) network ------------------------------------------------------------
step "Docker network"
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
  ok "$NETWORK exists"
else
  log "docker network create $NETWORK"
  docker network create "$NETWORK" >/dev/null
  ok "$NETWORK created"
fi

# ----- container helpers -----------------------------------------------------
container_exists()  { docker ps -a --filter "name=^${1}$" --format '{{.Names}}' | grep -q "^${1}$"; }
container_running() { docker ps    --filter "name=^${1}$" --format '{{.Names}}' | grep -q "^${1}$"; }

drop_container() {
  local name="$1"
  if container_exists "$name"; then
    log "stopping + removing existing $name"
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
}

wait_ready() {
  local name="$1" port="$2"
  local deadline=$(( $(date +%s) + AEM_READY_TIMEOUT ))
  log "waiting for $name to respond on :$port (timeout ${AEM_READY_TIMEOUT}s)"
  while :; do
    if container_running "$name"; then
      code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/libs/granite/core/content/login.html" 2>/dev/null || echo 000)
      if [ "$code" = "200" ]; then ok "$name is ready"; return 0; fi
      printf '   %s  %s :%s -> %s\n' "$(c_grey [$(date +%H:%M:%S)])" "$name" "$port" "$code"
    else
      warn "$name not running yet — recent logs:"
      docker logs --tail 5 "$name" 2>&1 | sed 's/^/      /' || true
    fi
    [ "$(date +%s)" -ge "$deadline" ] && die "$name did not become ready within $AEM_READY_TIMEOUT s"
    sleep "$AEM_READY_POLL"
  done
}

# ----- 5) AUTHOR -------------------------------------------------------------
step "Author ($AUTHOR_NAME on :$AUTHOR_PORT)"

[ "$RECREATE" = "1" ] && drop_container "$AUTHOR_NAME"

if container_running "$AUTHOR_NAME"; then
  ok "already running"
else
  if container_exists "$AUTHOR_NAME"; then
    log "starting existing container"
    docker start "$AUTHOR_NAME" >/dev/null
  else
    log "creating new container"
    docker run -d \
      --name "$AUTHOR_NAME" \
      --network "$NETWORK" \
      --network-alias author \
      -p "$AUTHOR_PORT:4502" \
      -p "$DEBUG_AUTHOR_PORT:5005" \
      -e AEM_RUNMODE=author,nosamplecontent \
      -e AEM_PORT=4502 \
      -e AEM_DEBUG=false \
      -e JVM_OPTS="$JVM_OPTS" \
      -v "$REPO_DIR/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
      -v "$REPO_DIR/aem-author/crx-quickstart:/opt/aem/crx-quickstart" \
      --restart unless-stopped \
      "$AEM_IMAGE" >/dev/null
    ok "author container created"
  fi
fi

wait_ready "$AUTHOR_NAME" "$AUTHOR_PORT"

if [ "$SKIP_PUBLISH" = "1" ]; then
  step "Skipping publish + dispatcher (--no-publish)"
  status_print
  exit 0
fi

# ----- 6) PUBLISH ------------------------------------------------------------
step "Publish ($PUBLISH_NAME on :$PUBLISH_PORT)"

[ "$RECREATE" = "1" ] && drop_container "$PUBLISH_NAME"

if container_running "$PUBLISH_NAME"; then
  ok "already running"
else
  if container_exists "$PUBLISH_NAME"; then
    log "starting existing container"
    docker start "$PUBLISH_NAME" >/dev/null
  else
    log "creating new container"
    docker run -d \
      --name "$PUBLISH_NAME" \
      --network "$NETWORK" \
      --network-alias publish \
      -p "$PUBLISH_PORT:4503" \
      -p "$DEBUG_PUBLISH_PORT:5005" \
      -e AEM_RUNMODE=publish \
      -e AEM_PORT=4503 \
      -e AEM_DEBUG=false \
      -e JVM_OPTS="$JVM_OPTS" \
      -v "$REPO_DIR/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
      -v "$REPO_DIR/aem-publish/crx-quickstart:/opt/aem/crx-quickstart" \
      --restart unless-stopped \
      "$AEM_IMAGE" >/dev/null
    ok "publish container created"
  fi
fi

wait_ready "$PUBLISH_NAME" "$PUBLISH_PORT"

# ----- 7) DISPATCHER ---------------------------------------------------------
if [ "$SKIP_DISPATCHER" = "1" ]; then
  step "Skipping dispatcher"
else
  step "Dispatcher ($DISP_NAME on :$DISP_PORT)"

  DISP_REWRITES="$DISP_SRC/conf.d/rewrites/rewrite.rules"
  DISP_FILTERS="$DISP_SRC/conf.dispatcher.d/filters/filters.any"

  for f in "$DISP_SRC" "$DISP_REWRITES" "$DISP_FILTERS" "$DISP_INVALIDATE"; do
    [ -e "$f" ] || die "dispatcher config file missing: $f"
  done
  ok "dispatcher config bundle present"

  [ "$RECREATE" = "1" ] && drop_container "$DISP_NAME"

  if container_running "$DISP_NAME"; then
    ok "already running"
  else
    if container_exists "$DISP_NAME"; then
      log "starting existing container"
      docker start "$DISP_NAME" >/dev/null
    else
      log "creating new container"
      docker run -d \
        --name "$DISP_NAME" \
        --network "$NETWORK" \
        --network-alias dispatcher \
        -p "$DISP_PORT:80" \
        -v "$DISP_SRC:/mnt/dev/src:ro" \
        -v "$DISP_REWRITES:/etc/httpd/conf.d/rewrites/rewrite.rules:ro" \
        -v "$DISP_FILTERS:/etc/httpd/conf.dispatcher.d/filters/filters.any:ro" \
        -v "$DISP_INVALIDATE:/docker_entrypoint.d/45-overwrite-invalidate.sh:ro" \
        -e AEM_HOST=publish \
        -e AEM_PORT=4503 \
        -e DISP_LOG_LEVEL=warn \
        -e REWRITE_LOG_LEVEL=warn \
        --restart unless-stopped \
        "$DISP_IMAGE" >/dev/null
      ok "dispatcher container created"
    fi
  fi

  sleep 4
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$DISP_PORT/" 2>/dev/null || echo 000)
  if [ "$code" = "302" ] || [ "$code" = "200" ] || [ "$code" = "404" ]; then
    ok "dispatcher answering ($code)"
  else
    warn "dispatcher returned $code — check: docker logs $DISP_NAME"
  fi
fi

# ----- 8) summary ------------------------------------------------------------
step "$(c_green 'Stack up.')"
status_print

cat <<EOF

  $(c_bold URLs)
    Author     http://localhost:$AUTHOR_PORT       (admin / admin first time; rotate via UI)
    Publish    http://localhost:$PUBLISH_PORT       (anonymous reads OK)
EOF
[ "$SKIP_DISPATCHER" = "1" ] || echo "    Dispatch   http://localhost:$DISP_PORT       (Apache + dispatcher in front of publish)"
cat <<EOF

  $(c_bold Sanity)
    curl -I http://localhost:$AUTHOR_PORT/libs/granite/core/content/login.html   # expect 200
EOF
[ "$SKIP_DISPATCHER" = "1" ] || cat <<EOF
    curl -I http://localhost:$DISP_PORT/                                          # 302/404 if no SPA yet
EOF
cat <<EOF

  $(c_bold Logs)
    docker logs -f $AUTHOR_NAME
    docker logs -f $PUBLISH_NAME
EOF
[ "$SKIP_DISPATCHER" = "1" ] || echo "    docker logs -f $DISP_NAME"
cat <<EOF

  $(c_bold Tear down)
    docker rm -f $AUTHOR_NAME $PUBLISH_NAME $DISP_NAME
    docker network rm $NETWORK
EOF
