# AEM SDK Directory

Place your Adobe Experience Manager (AEM) as a Cloud Service SDK quickstart jar in this directory. It is mounted as a read-only volume into the Docker containers.

## Required Files

1. **AEM Quickstart Jar**
   * File must be renamed to **`aem-quickstart.jar`**.
   * Example: Rename `aem-sdk-quickstart-2026.05.21.jar` to `aem-quickstart.jar`.

The AEM as a Cloud Service SDK no longer requires `license.properties` for local SDK startup.

## Expected Directory Structure

Before running `docker compose up`, make sure this folder contains:
```text
~/aem_docker/aem-sdk/
├── aem-quickstart.jar
└── README.md
```
