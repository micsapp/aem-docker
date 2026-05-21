#!/bin/bash
set -e

echo "========================================================="
echo " Starting AEM Docker Entrypoint"
echo "========================================================="

# 1. Validation Checks
if [ ! -f "/opt/aem/aem-quickstart.jar" ]; then
    echo "ERROR: /opt/aem/aem-quickstart.jar not found!"
    echo "Please place your AEM Quickstart Jar file in ~/aem_docker/aem-sdk/ and rename it to 'aem-quickstart.jar'."
    echo "Refer to aem_docker.md for setup details."
    exit 1
fi

# 2. Configure Remote Debugging if AEM_DEBUG=true
DEBUG_OPTS=""
if [ "$AEM_DEBUG" = "true" ]; then
    echo "JVM Remote Debugging is ENABLED on port 5005"
    # Support Java 9+ debugging address format
    DEBUG_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
fi

# 3. Base JVM System Properties
# AEM needs headless mode. CLDR locale provider ensures consistent formatting across different hosts.
BASE_JVM_OPTS="-Djava.awt.headless=true -Djava.locale.providers=CLDR,COMPAT,SPI"

echo "Configuration:"
echo "  - Runmode:   $AEM_RUNMODE"
echo "  - Port:      $AEM_PORT"
echo "  - JVM Opts:  $JVM_OPTS $BASE_JVM_OPTS"
if [ ! -z "$DEBUG_OPTS" ]; then
    echo "  - Debug:     $DEBUG_OPTS"
fi
echo "========================================================="
echo "Launching AEM (first startup takes 5-10 minutes)..."

# Use exec to replace the shell process with the Java process.
# This ensures that SIGTERM signals are caught by AEM for a graceful shutdown.
exec java $JVM_OPTS $BASE_JVM_OPTS $DEBUG_OPTS \
    -jar aem-quickstart.jar \
    -nofork \
    -verbose \
    -r "$AEM_RUNMODE" \
    -p "$AEM_PORT"
