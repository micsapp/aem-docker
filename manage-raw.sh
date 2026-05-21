#!/bin/bash

# AEM Raw Docker Management Script
# Allows starting, stopping, restarting, and deleting separated containers.

IMAGE_NAME="aem-base"
NETWORK_NAME="aem-net"

# Ensure script runs from the directory it is located in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    echo "Usage: $0 [start|stop|restart|delete] [author|publish|all]"
    echo "       $0 connect"
    echo "Examples:"
    echo "  $0 start author     # Starts only the author container"
    echo "  $0 stop all         # Stops both containers"
    echo "  $0 delete publish   # Removes the publish container"
    echo "  $0 connect          # Configures replication agent on Author and tests connection"
    exit 1
}

ACTION=$1
TARGET=$2

if [ "$ACTION" = "connect" ]; then
    TARGET="all"
elif [ $# -lt 2 ]; then
    usage
fi

# Ensure custom docker network exists
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

manage_container() {
    local service=$1
    local container_name="aem-$service"
    local port=""
    local debug_port=""
    local runmode=""

    if [ "$service" = "author" ]; then
        port="4502"
        debug_port="5005"
        runmode="author,nosamplecontent"
    elif [ "$service" = "publish" ]; then
        port="4503"
        debug_port="5006"
        runmode="publish"
    else
        echo "ERROR: Unknown service target '$service'. Use 'author' or 'publish'."
        return 1
    fi

    case "$ACTION" in
        start)
            # Check if container is already running
            if [ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" = "true" ]; then
                echo "[+] Container $container_name is already running."
            # Check if container exists but is currently stopped
            elif [ "$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)" = "exited" ] || \
                 [ "$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)" = "created" ]; then
                echo "[*] Starting existing container $container_name..."
                docker start "$container_name"
            else
                # Create and start a brand new container
                # Verify base image exists, build if missing
                if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                    echo "[*] Base image '$IMAGE_NAME' not found. Building now..."
                    docker build -t "$IMAGE_NAME" .
                fi

                # Verify installation files are present
                if [ ! -f "aem-sdk/aem-quickstart.jar" ] || [ ! -f "aem-sdk/license.properties" ]; then
                    echo "ERROR: Missing AEM quickstart jar or license.properties in aem-sdk/."
                    echo "Please place them in $(pwd)/aem-sdk/ before starting."
                    exit 1
                fi

                echo "[*] Creating and launching container $container_name..."
                docker run -d \
                    --name "$container_name" \
                    --network "$NETWORK_NAME" \
                    -p "$port:$port" \
                    -p "$debug_port:5005" \
                    -e AEM_RUNMODE="$runmode" \
                    -e AEM_PORT="$port" \
                    -v "$(pwd)/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
                    -v "$(pwd)/aem-sdk/license.properties:/opt/aem/license.properties:ro" \
                    -v "$(pwd)/aem-$service/crx-quickstart:/opt/aem/crx-quickstart" \
                    --restart unless-stopped \
                    "$IMAGE_NAME"
            fi
            ;;
        stop)
            if [ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" = "true" ]; then
                echo "[*] Stopping container $container_name..."
                docker stop "$container_name"
            else
                echo "[-] Container $container_name is not running."
            fi
            ;;
        restart)
            if [ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" = "true" ]; then
                echo "[*] Restarting container $container_name..."
                docker restart "$container_name"
            else
                echo "[-] Container $container_name is not running. Starting it..."
                manage_container "$service"
            fi
            ;;
        delete)
            echo "[*] Stopping container $container_name (if running)..."
            docker stop "$container_name" >/dev/null 2>&1 || true
            echo "[*] Deleting container $container_name..."
            docker rm "$container_name" >/dev/null 2>&1 || echo "[-] Container $container_name does not exist."
            ;;
        *)
            usage
            ;;
    esac
}

connect_instances() {
    # Default credentials
    local aem_user="${AEM_USER:-admin}"
    local aem_pass="${AEM_PASSWORD:-admin}"

    echo "[*] Checking AEM Author (localhost:4502) readiness..."
    # Quick healthcheck to see if Author is up
    if ! curl -s -o /dev/null -u "$aem_user:$aem_pass" http://localhost:4502/; then
        echo "ERROR: Cannot reach AEM Author on http://localhost:4502/ with credentials '$aem_user'."
        echo "       Please ensure that the author container is running and fully started."
        return 1
    fi

    echo "[*] Configuring replication agent on Author to target Publish (http://aem-publish:4503)..."
    local response
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -u "$aem_user:$aem_pass" \
        -X POST \
        -F "transportUri=http://aem-publish:4503/bin/receive/id/default" \
        -F "transportUser=$aem_user" \
        -F "transportPassword=$aem_pass" \
        -F "enabled=true" \
        http://localhost:4502/etc/replication/agents.author/publish/jcr:content)

    if [ "$response" = "200" ] || [ "$response" = "201" ]; then
        echo "[+] Replication agent configured successfully (HTTP $response)."
    else
        echo "[-] Failed to configure replication agent (HTTP $response)."
        return 1
    fi

    echo "[*] Testing connection from Author to Publish..."
    local test_output
    test_output=$(curl -s -u "$aem_user:$aem_pass" -X POST http://localhost:4502/etc/replication/agents.author/publish.test.html)

    if echo "$test_output" | grep -iq "Replication test succeeded" || echo "$test_output" | grep -iq "Integration test succeeded"; then
        echo "[+] Replication Connection TEST SUCCEEDED!"
    else
        echo "[-] Replication Connection TEST FAILED."
        echo "    Here is the connection test log:"
        echo "--------------------------------------------------------"
        # Extract pre content containing logs, strip tags
        echo "$test_output" | sed -n '/<pre>/,/<\/pre>/p' | sed -e 's/<[^>]*>//g'
        echo "--------------------------------------------------------"
        echo "    Tip: Make sure both 'aem-author' and 'aem-publish' containers"
        echo "         are running and attached to the '$NETWORK_NAME' network."
    fi
}

if [ "$ACTION" = "connect" ]; then
    connect_instances
elif [ "$TARGET" = "all" ]; then
    manage_container "author"
    manage_container "publish"
else
    manage_container "$TARGET"
fi
