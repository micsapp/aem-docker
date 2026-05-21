FROM eclipse-temurin:11-jdk-jammy

# Set up environment variables
ENV AEM_HOME=/opt/aem \
    AEM_RUNMODE=author \
    AEM_PORT=4502 \
    JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m"

# Install curl, procps (provides ps), net-tools, and unzip
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    procps \
    net-tools \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Create AEM working directory
WORKDIR $AEM_HOME

# Copy the entrypoint script into the image
COPY entrypoint.sh /opt/aem/entrypoint.sh
RUN chmod +x /opt/aem/entrypoint.sh

# Expose ports:
# - 4502: Author
# - 4503: Publish
# - 5005: JVM Debugging
EXPOSE 4502 4503 5005

# Set entrypoint
ENTRYPOINT ["/opt/aem/entrypoint.sh"]
