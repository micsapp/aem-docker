# AEM Docker Development Environment

This repository provides a Docker-based local development environment for Adobe Experience Manager (AEM) as a Cloud Service SDK.

It is intentionally small. The repository contains only Docker configuration, startup scripts, and documentation. It does **not** include the proprietary AEM SDK quickstart jar or generated AEM runtime repository data.

## What This Project Provides

- A Docker image for running AEM with Eclipse Temurin OpenJDK 11.
- A single-container workflow for running a local AEM Author instance.
- An optional Docker Compose workflow for running Author and Publish instances.
- Persistent local AEM repository data through bind-mounted `crx-quickstart` folders.
- A startup entrypoint that validates the required quickstart jar and launches AEM with `-nofork`.
- Notes for enabling Content Fragment Models in a fresh local SDK repository.

## Repository Contents

```text
.
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── README.md
├── aem_docker.md
├── content_fragment_model.md
└── aem-sdk/
    └── README.md
```

Generated or proprietary files are ignored by Git:

```text
aem-sdk/aem-quickstart.jar
aem-author/crx-quickstart/
aem-publish/crx-quickstart/
```

## Prerequisites

Install the following on your machine:

- Docker Engine or Docker Desktop.
- Docker Compose v2, only if you want to use `docker compose`.
- An AEM as a Cloud Service SDK quickstart jar from Adobe Software Distribution.

The SDK jar tested with this project was:

```text
Adobe AEM Cloud Service/SDK
Product-Version: 2024.4.15977.20240418T174835Z-240300
```

That SDK requires Java 11, so the Dockerfile currently uses:

```dockerfile
eclipse-temurin:11-jdk-jammy
```

Newer AEM SDK releases may require a newer Java version. If your SDK fails during startup with a Java version error, update the base image in `Dockerfile` to the Java version required by your SDK.

## Get the AEM SDK Jar

Download the AEM as a Cloud Service SDK from Adobe Software Distribution:

```text
https://experience.adobe.com/#/downloads/content/software-distribution/en/aemcloud.html
```

After downloading and extracting the SDK, locate the quickstart jar. It is usually named like:

```text
aem-sdk-quickstart-*.jar
```

Copy it into this project and rename it:

```bash
cp /path/to/aem-sdk-quickstart-*.jar ./aem-sdk/aem-quickstart.jar
```

Expected local structure:

```text
aem-sdk/
├── README.md
└── aem-quickstart.jar
```

The AEM as a Cloud Service SDK does not require `license.properties` for local startup.

## Build the Docker Image

From the repository root:

```bash
docker build -t aem-local .
```

The image includes:

- Java runtime from Eclipse Temurin.
- `curl`, `procps`, `net-tools`, and `unzip`.
- The project `entrypoint.sh`.

The AEM quickstart jar is **not** copied into the image. It is mounted at runtime from `./aem-sdk/aem-quickstart.jar`.

## Run AEM Author Without Docker Compose

This is the recommended first run because it starts only one container.

```bash
docker run --name aem-author \
  -p 4502:4502 \
  -p 5005:5005 \
  -e AEM_RUNMODE=author,nosamplecontent \
  -e AEM_PORT=4502 \
  -e AEM_DEBUG=false \
  -e JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m" \
  -v "$PWD/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
  -v "$PWD/aem-author/crx-quickstart:/opt/aem/crx-quickstart" \
  aem-local
```

To run it in the background:

```bash
docker run -d --name aem-author \
  -p 4502:4502 \
  -p 5005:5005 \
  -e AEM_RUNMODE=author,nosamplecontent \
  -e AEM_PORT=4502 \
  -e AEM_DEBUG=false \
  -e JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m" \
  -v "$PWD/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
  -v "$PWD/aem-author/crx-quickstart:/opt/aem/crx-quickstart" \
  aem-local
```

First startup can take several minutes. AEM has to unpack the SDK jar, initialize `crx-quickstart`, install bundles, and build startup indexes.

Open AEM Author after startup:

```text
http://localhost:4502
```

Default local credentials are usually:

```text
admin / admin
```

## Run With Docker Compose

The compose file defines two services:

| Service | Host Port | Container Port | Runmode |
| --- | ---: | ---: | --- |
| `author` | `4502` | `4502` | `author,nosamplecontent` |
| `publish` | `4503` | `4503` | `publish` |

Start both services:

```bash
docker compose up -d
```

Start only Author:

```bash
docker compose up -d author
```

Start only Publish:

```bash
docker compose up -d publish
```

View logs:

```bash
docker compose logs -f
```

View Author logs only:

```bash
docker compose logs -f author
```

Stop services:

```bash
docker compose stop
```

Remove containers while keeping local repository data:

```bash
docker compose down
```

## Useful Docker Commands

Check running containers:

```bash
docker ps
```

Follow Author logs:

```bash
docker logs -f aem-author
```

Stop Author:

```bash
docker stop aem-author
```

Start Author again:

```bash
docker start aem-author
```

Remove the stopped Author container:

```bash
docker rm aem-author
```

Open a shell inside the container:

```bash
docker exec -it aem-author bash
```

Check whether AEM responds from inside the container:

```bash
docker exec aem-author curl -I -u admin:admin http://localhost:4502
```

## Persistent Data

AEM runtime data is stored on the host:

```text
aem-author/crx-quickstart/
aem-publish/crx-quickstart/
```

These folders are ignored by Git and should not be committed.

To reset the local Author repository:

```bash
docker stop aem-author
docker rm aem-author
rm -rf aem-author/crx-quickstart
```

Then run the Author container again. AEM will perform a fresh first-time install.

## Logs

Docker logs:

```bash
docker logs -f aem-author
```

AEM logs on the host:

```bash
tail -f aem-author/crx-quickstart/logs/error.log
```

For Compose:

```bash
tail -f aem-publish/crx-quickstart/logs/error.log
```

## Environment Variables

The entrypoint uses these variables:

| Variable | Default | Description |
| --- | --- | --- |
| `AEM_RUNMODE` | `author` | AEM run modes, for example `author,nosamplecontent` or `publish`. |
| `AEM_PORT` | `4502` | HTTP port inside the container. |
| `AEM_DEBUG` | `false` | Set to `true` to enable remote JVM debugging on container port `5005`. |
| `JVM_OPTS` | `-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m` | JVM memory settings. |

Enable remote debug:

```bash
docker run -d --name aem-author \
  -p 4502:4502 \
  -p 5005:5005 \
  -e AEM_RUNMODE=author,nosamplecontent \
  -e AEM_PORT=4502 \
  -e AEM_DEBUG=true \
  -e JVM_OPTS="-Xms1024m -Xmx2048m -XX:MaxMetaspaceSize=512m" \
  -v "$PWD/aem-sdk/aem-quickstart.jar:/opt/aem/aem-quickstart.jar:ro" \
  -v "$PWD/aem-author/crx-quickstart:/opt/aem/crx-quickstart" \
  aem-local
```

Then attach your debugger to:

```text
localhost:5005
```

## Content Fragment Models

On a fresh local SDK repository, Content Fragment Model creation may not be available until the selected `/conf` configuration is enabled.

For the `global` configuration, the important path is:

```text
/conf/global/settings/dam/cfm/models
```

If the model console does not show the **Create** action, enable Content Fragment Models in AEM:

```text
Tools > General > Configuration Browser > Global > Properties > Content Fragment Models
```

The local instance used while preparing this repository was fixed by copying the stock model configuration:

```text
/libs/settings/dam/cfm/models
```

to:

```text
/conf/global/settings/dam/cfm/models
```

More details are in:

```text
content_fragment_model.md
```

After the configuration exists, open:

```text
http://localhost:4502/libs/dam/cfm/models/console/content/models.html/conf/global
```

## Troubleshooting

### `aem-quickstart.jar not found`

The runtime jar is missing. Add it here:

```text
aem-sdk/aem-quickstart.jar
```

### Java Version Error

If startup fails with a message similar to:

```text
Quickstart does not run with newer versions as Java Specification 11 VM
```

then the SDK jar expects Java 11. Keep:

```dockerfile
FROM eclipse-temurin:11-jdk-jammy
```

If a newer SDK says it requires Java 21, update the Dockerfile:

```dockerfile
FROM eclipse-temurin:21-jdk-jammy
```

Then rebuild:

```bash
docker build -t aem-local .
```

### Port Already in Use

If port `4502` is already used:

```bash
docker ps
```

Stop the conflicting container or map to a different host port:

```bash
docker run --name aem-author \
  -p 14502:4502 \
  ...
```

Then open:

```text
http://localhost:14502
```

### Container Name Already Exists

If Docker reports that `aem-author` already exists:

```bash
docker start aem-author
```

or remove and recreate it:

```bash
docker rm aem-author
```

### AEM Is Running but Browser Is Not Ready

First startup can take several minutes. Watch:

```bash
docker logs -f aem-author
```

Look for:

```text
Quickstart started
```

### Running on Windows or WSL

The project can run from a Windows-mounted path, but AEM repository IO may be slower under `/mnt/c/...`. For better performance on WSL, consider keeping the project under the Linux filesystem, for example:

```text
~/projects/aem-docker
```

## Security and Git Hygiene

Do not commit:

- AEM SDK jars.
- `license.properties`.
- `crx-quickstart` runtime folders.
- Logs, indexes, repository data, or generated AEM files.

The `.gitignore` is configured to keep those files out of Git.
