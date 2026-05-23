#!/usr/bin/env bash
# spa-mvn build & deploy script for AEM author (and optionally publish)
#
# Auto-detects first build vs rebuild based on filesystem state.
# Pick a narrower scope manually with --frontend / --core if you know
# only that part changed; the smaller scopes finish in ~10-25 s vs
# ~60 s for a full clean.
#
# Build runner auto-detected:
#   - if `mvn` is on PATH and JAVA_HOME points at a real JDK, runs on the host
#   - otherwise wraps mvn in `docker run maven:3.9-eclipse-temurin-21`
#   so a developer with only docker installed can build without setting up JDK 21
#   + Maven locally. Force one or the other with --docker / --host-mvn.

set -euo pipefail

# ----- paths / defaults ------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAVA_HOME_DEFAULT="/usr/lib/jvm/java-21-openjdk-amd64"

AEM_AUTHOR="${AEM_AUTHOR:-http://localhost:4502}"
AEM_PUBLISH="${AEM_PUBLISH:-http://localhost:4503}"
AEM_USER="${AEM_USER:-admin}"
AEM_PASS="${AEM_PASS:-admin}"

# Containerized-build defaults (used when BUILDER=docker)
MAVEN_IMAGE="${MAVEN_IMAGE:-maven:3.9-eclipse-temurin-21}"
MAVEN_CACHE_VOL="${MAVEN_CACHE_VOL:-maven-cache}"

MODE="auto"          # auto | clean | install | frontend | core
BUILDER="auto"       # auto | host | docker
REPLICATE=0
SKIP_TESTS=1         # default skip — flip with --tests
VERIFY=1             # always curl the page after install — flip with --no-verify

# ----- helpers ---------------------------------------------------------------
c_grey()  { printf '\033[90m%s\033[0m' "$*"; }
c_blue()  { printf '\033[34m%s\033[0m' "$*"; }
c_green() { printf '\033[32m%s\033[0m' "$*"; }
c_red()   { printf '\033[31m%s\033[0m' "$*"; }
c_bold()  { printf '\033[1m%s\033[0m' "$*"; }

log()  { printf '%s %s\n' "$(c_grey "[$(date +%H:%M:%S)]")" "$*"; }
step() { printf '\n%s %s\n' "$(c_blue '==>')" "$(c_bold "$*")"; }
die()  { printf '%s %s\n' "$(c_red 'ERROR:')" "$*" >&2; exit 1; }

# ----- usage -----------------------------------------------------------------
usage() {
  cat <<EOF
$(c_bold "spa-mvn/deploy.sh") — build and deploy the SPA MVN project to AEM author

USAGE
    ./deploy.sh [mode] [flags]

MODES (mutually exclusive; default: auto)
    --auto, -a       Detect first build vs rebuild from filesystem state
    --clean, -c      Force \`mvn clean install\` (cleans target/ first)
    --install, -i    \`mvn install\` (no clean; reuses prior targets)
    --frontend, -f   Build only ui.frontend + ui.apps + all (-pl ... -am)
    --core           Build only core + all (-pl ... -am)

BUILD RUNNER (mutually exclusive; default: auto)
    --docker         Force the containerized build (Maven runs in $MAVEN_IMAGE)
    --host-mvn       Force the host build (requires \`mvn\` on PATH + valid JAVA_HOME)

FLAGS
    --publish, -p    Also replicate spa-mvn paths to AEM publish
    --tests          Run the it.tests + ui.tests modules (default: skip)
    --no-verify      Skip the post-install curl check
    --help, -h       This text

AUTO-DETECT RULES
    Build mode: first build (no ui.frontend/node_modules) → --clean; otherwise --install
    Runner:     \`mvn\` on PATH + valid JAVA_HOME → host; otherwise docker fallback

ENV VARS
    JAVA_HOME       defaults to $JAVA_HOME_DEFAULT (host runner only)
    MAVEN_IMAGE     defaults to $MAVEN_IMAGE (docker runner only)
    MAVEN_CACHE_VOL defaults to $MAVEN_CACHE_VOL (named volume so .m2 survives)
    AEM_AUTHOR      $AEM_AUTHOR
    AEM_PUBLISH     $AEM_PUBLISH
    AEM_USER        $AEM_USER
    AEM_PASS        $AEM_PASS

EXAMPLES
    ./deploy.sh                      # smart default — host mvn if present, else docker
    ./deploy.sh --docker             # force containerized build (no JDK needed on host)
    ./deploy.sh -f                   # just rebuilt App.vue, push the Vue bundle
    ./deploy.sh -c -p                # clean rebuild and replicate to publish
    ./deploy.sh --core               # only core/ Java changed
EOF
}

# ----- arg parsing -----------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto|-a)     MODE="auto" ;;
    --clean|-c)    MODE="clean" ;;
    --install|-i)  MODE="install" ;;
    --frontend|-f) MODE="frontend" ;;
    --core)        MODE="core" ;;
    --docker)      BUILDER="docker" ;;
    --host-mvn)    BUILDER="host" ;;
    --publish|-p)  REPLICATE=1 ;;
    --tests)       SKIP_TESTS=0 ;;
    --no-verify)   VERIFY=0 ;;
    --help|-h)     usage; exit 0 ;;
    *)             die "unknown arg: $1   (try --help)" ;;
  esac
  shift
done

# ----- preflight -------------------------------------------------------------
step "Preflight"

[ -d "$PROJECT_DIR" ] || die "PROJECT_DIR not a dir: $PROJECT_DIR"
[ -f "$PROJECT_DIR/pom.xml" ] || die "no pom.xml in $PROJECT_DIR (run from spa-mvn/)"

command -v curl >/dev/null || die "curl not on PATH"

# ----- decide BUILDER: host (system mvn) vs docker (maven container) --------
host_mvn_ok() {
  command -v mvn  >/dev/null || return 1
  command -v node >/dev/null || return 1
  local jh="${JAVA_HOME:-$JAVA_HOME_DEFAULT}"
  [ -d "$jh" ] || return 1
  return 0
}

# DOCKER_CMD resolves to `docker` or `sudo docker` depending on group membership
detect_docker_cmd() {
  command -v docker >/dev/null || return 1
  if docker info >/dev/null 2>&1; then
    DOCKER_CMD="docker"; return 0
  fi
  if sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD="sudo docker"; return 0
  fi
  return 1
}

if [ "$BUILDER" = "auto" ]; then
  if host_mvn_ok; then
    BUILDER="host"
  elif detect_docker_cmd; then
    BUILDER="docker"
  else
    die "neither host mvn+JDK nor docker available — install one of them, or set JAVA_HOME"
  fi
fi

case "$BUILDER" in
  host)
    export JAVA_HOME="${JAVA_HOME:-$JAVA_HOME_DEFAULT}"
    [ -d "$JAVA_HOME" ] || die "JAVA_HOME does not exist: $JAVA_HOME"
    command -v mvn  >/dev/null || die "--host-mvn but mvn not on PATH"
    command -v node >/dev/null || die "--host-mvn but node not on PATH (needed for ui.frontend)"
    log "builder: host    JAVA_HOME=$JAVA_HOME"
    log "$(mvn --version | head -1)"
    log "node $(node --version)"
    ;;
  docker)
    detect_docker_cmd || die "--docker but docker not accessible (add user to docker group or run via sudo)"
    log "builder: docker  image=$MAVEN_IMAGE  cache=$MAVEN_CACHE_VOL  ($DOCKER_CMD)"
    # Pre-pull the image so subsequent runs don't spam pull output mid-build
    if ! $DOCKER_CMD image inspect "$MAVEN_IMAGE" >/dev/null 2>&1; then
      log "pulling $MAVEN_IMAGE (first time only)"
      $DOCKER_CMD pull "$MAVEN_IMAGE" >/dev/null
    fi
    ;;
  *) die "unhandled BUILDER=$BUILDER" ;;
esac

# mvn_run is the single dispatch point for every Maven invocation below.
mvn_run() {
  if [ "$BUILDER" = "docker" ]; then
    log "(docker) mvn $*"
    # --network host so Maven inside the container can hit localhost:4502 for autoInstallPackage.
    # Linux-only — on macOS/Windows replace with -p 4502:4502 + -Daem.host=host.docker.internal.
    $DOCKER_CMD run --rm \
      --network host \
      -v "$PROJECT_DIR:/build" \
      -v "$MAVEN_CACHE_VOL:/root/.m2" \
      -w /build \
      "$MAVEN_IMAGE" \
      mvn "$@"
  else
    log "mvn $*"
    mvn "$@"
  fi
}

# Author must be reachable for autoInstallPackage
if ! curl -fsS -o /dev/null -u "$AEM_USER:$AEM_PASS" "$AEM_AUTHOR/libs/granite/core/content/login.html"; then
  die "AEM author not reachable at $AEM_AUTHOR (auth: $AEM_USER:***). Is the container up?"
fi
log "AEM author reachable at $AEM_AUTHOR"

if [ "$REPLICATE" = "1" ]; then
  if ! curl -fsS -o /dev/null "$AEM_PUBLISH/libs/granite/core/content/login.html"; then
    die "AEM publish not reachable at $AEM_PUBLISH — needed for --publish"
  fi
  log "AEM publish reachable at $AEM_PUBLISH"
fi

# ----- mode auto-detection ---------------------------------------------------
if [ "$MODE" = "auto" ]; then
  step "Auto-detect build mode"
  if [ ! -d "$PROJECT_DIR/ui.frontend/node_modules" ]; then
    log "ui.frontend/node_modules missing → first build → using --clean"
    MODE="clean"
  elif [ ! -d "$PROJECT_DIR/all/target" ]; then
    log "all/target missing → fresh install (no clean needed)"
    MODE="install"
  else
    log "Prior build present → fast incremental --install"
    MODE="install"
  fi
fi

# ----- build -----------------------------------------------------------------
cd "$PROJECT_DIR"

MVN_ARGS=( -B -PautoInstallPackage \
           -Daem.host=localhost -Daem.port=4502 \
           -Dvault.user="$AEM_USER" -Dvault.password="$AEM_PASS" )
[ "$SKIP_TESTS" = "1" ] && MVN_ARGS+=( -DskipTests -Dmaven.test.skip=true )

step "Build  ($(c_bold "$MODE")  via $(c_bold "$BUILDER"))"
case "$MODE" in
  clean)
    mvn_run "${MVN_ARGS[@]}" clean install
    ;;
  install)
    mvn_run "${MVN_ARGS[@]}" install
    ;;
  frontend)
    mvn_run "${MVN_ARGS[@]}" -pl ui.frontend,ui.apps,all -am install
    ;;
  core)
    mvn_run "${MVN_ARGS[@]}" -pl core,all -am install
    ;;
  *)
    die "unhandled MODE=$MODE"
    ;;
esac

log "build OK"

# ----- replicate to publish --------------------------------------------------
if [ "$REPLICATE" = "1" ]; then
  step "Replicate to publish"

  rep() {
    local p="$1"
    local out msg
    out=$(curl -sS -u "$AEM_USER:$AEM_PASS" -F "cmd=Activate" -F "path=$p" "$AEM_AUTHOR/bin/replicate.json")
    msg=$(printf '%s' "$out" | grep -oE '"status.message":"[^"]*"' | head -1 | sed 's/.*:"//;s/\\n"//')
    printf '  %-72s %s\n' "$p" "${msg:-no-reply}"
  }

  # apps subtree
  for p in \
    /apps/spa-mvn \
    /apps/spa-mvn/components \
    /apps/spa-mvn/components/page \
    /apps/spa-mvn/components/page/page.html \
    /apps/spa-mvn/components/page/customheaderlibs.html \
    /apps/spa-mvn/components/page/customfooterlibs.html \
    /apps/spa-mvn/clientlibs \
    /apps/spa-mvn/clientlibs/clientlib-site \
    /apps/spa-mvn/clientlibs/clientlib-site/js.txt \
    /apps/spa-mvn/clientlibs/clientlib-site/css.txt \
    /apps/spa-mvn/clientlibs/clientlib-site/js \
    /apps/spa-mvn/clientlibs/clientlib-site/js/site.js \
    /apps/spa-mvn/clientlibs/clientlib-site/css \
    /apps/spa-mvn/clientlibs/clientlib-site/css/site.css; do
    rep "$p"
  done

  # conf (templates)
  for p in \
    /conf/spa-mvn \
    /conf/spa-mvn/settings \
    /conf/spa-mvn/settings/wcm \
    /conf/spa-mvn/settings/wcm/templates \
    /conf/spa-mvn/settings/wcm/policies \
    /conf/spa-mvn/settings/wcm/template-types \
    /conf/spa-mvn/_sling_configs; do
    rep "$p"
  done

  # content pages
  for p in \
    /content/spa-mvn \
    /content/spa-mvn/jcr:content \
    /content/spa-mvn/us \
    /content/spa-mvn/us/jcr:content \
    /content/spa-mvn/us/en \
    /content/spa-mvn/us/en/jcr:content; do
    rep "$p"
  done

  sleep 2
fi

# ----- verify ----------------------------------------------------------------
if [ "$VERIFY" = "1" ]; then
  step "Verify"

  printf '  %-30s ' "author /content/spa-mvn.html"
  code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$AEM_USER:$AEM_PASS" "$AEM_AUTHOR/content/spa-mvn.html")
  [ "$code" = "200" ] && c_green "HTTP $code" || c_red "HTTP $code"; echo

  printf '  %-30s ' "author /content/spa-mvn/us/en.html"
  code=$(curl -sS -o /dev/null -w '%{http_code}' -L -u "$AEM_USER:$AEM_PASS" "$AEM_AUTHOR/content/spa-mvn/us/en.html")
  [ "$code" = "200" ] && c_green "HTTP $code" || c_red "HTTP $code"; echo

  if [ "$REPLICATE" = "1" ]; then
    printf '  %-30s ' "publish (anon)"
    code=$(curl -sS -o /dev/null -w '%{http_code}' -L "$AEM_PUBLISH/content/spa-mvn.html")
    [ "$code" = "200" ] && c_green "HTTP $code" || c_red "HTTP $code"; echo
  fi

  echo
  echo "  Open in browser:"
  echo "    $AEM_AUTHOR/content/spa-mvn.html        (admin/admin)"
  [ "$REPLICATE" = "1" ] && echo "    $AEM_PUBLISH/content/spa-mvn.html       (anonymous)"
fi

step "$(c_green Done)"
