#!/bin/bash

# AEM Docker Compose Management Script
# Provides wrapper commands for compose up, down, restart, etc.

# Ensure script runs from the directory it is located in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    echo "Usage: $0 [up|down|start|stop|restart|logs]"
    echo "Commands:"
    echo "  up      - Builds image and starts all containers in detached mode"
    echo "  down    - Stops and removes all containers, networks, and volumes"
    echo "  start   - Starts stopped containers"
    echo "  stop    - Stops running containers without removing them"
    echo "  restart - Restarts running containers"
    echo "  logs    - Streams log outputs from all compose containers"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

ACTION=$1

# Determine command style (docker compose vs docker-compose)
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif docker-compose --version >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo "ERROR: Neither 'docker compose' nor 'docker-compose' was found on your system."
    echo "Please install Docker Compose to run this script."
    exit 1
fi

case "$ACTION" in
    up)
        # Verify files exist before attempting compose up
        if [ ! -f "aem-sdk/aem-quickstart.jar" ] || [ ! -f "aem-sdk/license.properties" ]; then
            echo "ERROR: Missing AEM quickstart jar or license.properties in aem-sdk/."
            echo "Please place them in $(pwd)/aem-sdk/ before starting."
            exit 1
        fi
        echo "[*] Launching AEM Stack using: $COMPOSE_CMD up -d"
        $COMPOSE_CMD up -d
        ;;
    down)
        echo "[*] Stopping and cleaning AEM Stack using: $COMPOSE_CMD down"
        $COMPOSE_CMD down
        ;;
    start)
        echo "[*] Starting AEM containers using: $COMPOSE_CMD start"
        $COMPOSE_CMD start
        ;;
    stop)
        echo "[*] Stopping AEM containers using: $COMPOSE_CMD stop"
        $COMPOSE_CMD stop
        ;;
    restart)
        echo "[*] Restarting AEM containers using: $COMPOSE_CMD restart"
        $COMPOSE_CMD restart
        ;;
    logs)
        echo "[*] Streaming AEM logs using: $COMPOSE_CMD logs -f"
        $COMPOSE_CMD logs -f
        ;;
    *)
        usage
        ;;
esac
