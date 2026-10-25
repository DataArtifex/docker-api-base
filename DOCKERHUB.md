# dartfx/docker-api-base

[![Docker Image](https://img.shields.io/docker/v/dartfx/docker-api-base?sort=semver&logo=docker&label=Docker%20Hub)](https://hub.docker.com/r/dartfx/docker-api-base)
[![Docker Pulls](https://img.shields.io/docker/pulls/dartfx/docker-api-base?logo=docker)](https://hub.docker.com/r/dartfx/docker-api-base)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`dartfx/docker-api-base` is the official API base Docker image for the **Data Artifex** platform. It extends the minimal `dartfx/docker-base` image to provide a secure, high-performance environment optimized for hosting FastAPI applications running with Uvicorn.

## Key Features

- **Python Virtual Environment**: Ready-to-use virtual environment located at `/opt/venv` (pre-configured in the `PATH`).
- **Package Manager**: Built-in support for [`uv`](https://github.com/astral-sh/uv) and Hatch for fast, reproducible dependency syncing.
- **FastAPI & Uvicorn**: Pre-installed FastAPI and Uvicorn (`uvicorn[standard]`) dependencies.
- **Security Defaults**:
  - Runs under a non-privileged system user: **`appuser`** (UID `10001`, GID `10001`).
  - Optimized for read-only root filesystems (`--read-only`).
  - Standard port `8000` exposed for API traffic.

---

## How to Extend This Image

To build a new service on top of this base image, use a multi-stage Dockerfile that leverages `uv` to sync dependencies into the pre-existing virtual environment (`/opt/venv`).

### 1. Project Structure

Ensure your service has a `pyproject.toml` at its root:

```
my-api-service/
├── Dockerfile
├── pyproject.toml
└── src/
    └── my_api_service/
        ├── __init__.py
        └── main.py
```

### 2. Example `pyproject.toml`

Define your service metadata and dependencies. Notice that you do not need to redeclare `fastapi` or `uvicorn` unless you require specific versions:

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my-api-service"
version = "0.1.0"
dependencies = [
    "httpx",
    "pydantic>=2.0"
]

[tool.hatch.metadata]
allow-direct-references = true

[tool.hatch.build.targets.wheel]
packages = ["src/my_api_service"]
```

### 3. Example `Dockerfile`

```dockerfile
# --- Builder Stage ---
FROM dartfx/docker-api-base:latest AS builder
WORKDIR /app

# Install uv for fast package management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Copy project configuration files first to optimize layer caching
COPY pyproject.toml ./

# Install project dependencies into the virtual environment /opt/venv
RUN uv pip install --no-cache -r pyproject.toml

# Copy project source code
COPY . /app

# Install the project itself (without reinstalling dependencies)
RUN uv pip install --no-cache --no-deps .

# --- Runtime Stage ---
FROM dartfx/docker-api-base:latest
WORKDIR /app

# Copy the updated virtual environment and application code with proper ownership
COPY --from=builder --chown=appuser:appgroup /opt/venv /opt/venv
COPY --chown=appuser:appgroup . /app

# Run as the default non-root user
USER appuser

# Start your service entrypoint
CMD ["uvicorn", "my_api_service.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## Quick Start (Testing the Base Image)

You can run the base image directly to verify the default mock API endpoint:

```bash
docker run --rm -p 8000:8000 dartfx/docker-api-base:latest
```

Query the running test server:

```bash
curl http://localhost:8000/
# Returns: {"status":"ok","message":"Data Artifex API Base is running."}
```

## Production Guidelines

1. **Read-Only Root Filesystem**: Configure your container orchestrator (e.g., Kubernetes or ECS) to run with a read-only root filesystem (`readOnlyRootFilesystem: true`). Mount a `tmpfs` volume at `/tmp` if your application needs to write temporary files.
2. **Pin Base Image Versions**: For production stability, pin the base image to a specific version tag or digest:
   ```dockerfile
   FROM dartfx/docker-api-base:0.1.0
   ```
3. **Secrets Management**: Never build secrets (API keys, database credentials) into your image layers. Always inject them at runtime via environment variables.

## Uvicorn Configuration & Tuning

Because Uvicorn's command-line interface is built using `click`, almost all CLI options can be configured by prefixing the option name with `UVICORN_` in uppercase and replacing hyphens with underscores.

### Workers & Concurrency

- **`WEB_CONCURRENCY`** or **`UVICORN_WORKERS`**: Sets the number of worker processes. A standard recommendation is `(2 * CPU cores) + 1` for general/I-O heavy workloads, or exactly `CPU cores` for CPU-heavy workloads.
- **`UVICORN_LIMIT_CONCURRENCY`**: The maximum number of concurrent connections or tasks to allow before returning `503 Service Unavailable`.
- **`UVICORN_LIMIT_MAX_REQUESTS`**: The maximum number of requests a worker will service before restarting (helps prevent memory leaks).

### Performance Engines

Since this image has standard extras pre-installed (`uvicorn[standard]`), Uvicorn automatically detects and uses high-performance C-extensions. You can also explicitly enforce them:

- **`UVICORN_LOOP=uvloop`**: Uses `uvloop` (an ultra-fast asyncio event loop written in Cython).
- **`UVICORN_HTTP=httptools`**: Uses `httptools` (a fast Python binding for the NodeJS HTTP parser).

### Connections & Timeouts

- **`UVICORN_TIMEOUT_KEEP_ALIVE`**: Closes keep-alive connections if no new data is received within this timeout (in seconds). Default is `5`.
- **`UVICORN_BACKLOG`**: The maximum number of connections to hold in the TCP backlog queue.

### Proxy & Header Trust (Kubernetes / Load Balancer)

When running behind a reverse proxy (e.g., Nginx, Traefik, Kong, or ALB), trust the proxy headers so client IPs and HTTPS schemes are passed correctly:

- **`UVICORN_PROXY_HEADERS=True`**: Enables parsing of proxy headers.
- **`UVICORN_FORWARDED_ALLOW_IPS=*`**: A comma-separated list of IP addresses allowed to set proxy headers (use `*` to trust everything in internal Docker bridge networks).

### Development vs. Production Guidelines

Depending on whether you are running in a local development environment or a production container orchestrator (Kubernetes, ECS), optimize your settings accordingly:

| Parameter                           | Development       | Production          | Rationale                                                          |
| :---------------------------------- | :---------------- | :------------------ | :----------------------------------------------------------------- |
| **Workers (`WEB_CONCURRENCY`)**     | `1`               | `(2 * vCPU) + 1`    | Dev needs breakpoint debugging; Prod needs multi-core scalability. |
| **Auto-Reload (`--reload`)**        | `True`            | `False`             | Filesystem watch overhead degrades production performance.         |
| **Event Loop (`UVICORN_LOOP`)**     | `auto`            | `uvloop`            | Explicitly enforce Cython-based loop for raw throughput.           |
| **HTTP Parser (`UVICORN_HTTP`)**    | `auto`            | `httptools`         | Enforce native C-level HTTP parser in production.                  |
| **Log Level (`UVICORN_LOG_LEVEL`)** | `debug` or `info` | `warning` or `info` | Prevent stdout lockups and disk usage issues.                      |
| **Keep-Alive Timeout**              | `5`               | `15` to `65`        | Match reverse proxy pool settings to prevent 502 Bad Gateways.     |
| **Concurrency Limit**               | None              | `1000` to `5000`    | Dropping requests via 503 protects containers from OOM crashes.    |

#### Key Scaling Factors:

- **vCPU Allocation & Scaling:** Each Uvicorn worker process is single-threaded due to Python's GIL. Scale workers according to the **container's CPU limit**, not the host machine's total cores (e.g. if the container limit is `0.5 vCPU`, use `1` worker to avoid CPU throttling). For CPU-heavy endpoints (ML inference, crypto), limit workers to exactly `vCPU` to avoid context-switching thrashing.
- **Memory Limits:** Each worker process uses ~70MB to 150MB of baseline memory. Scale your container memory limits proportionally ($\text{Total Memory} \ge (\text{Workers} \times \text{Avg Worker Memory}) + 20\%$). Set `UVICORN_LIMIT_MAX_REQUESTS` to force workers to periodically recycle and free memory.
- **Keep-Alive Alignment:** When running behind an Application Load Balancer or ingress proxy (ALB, Nginx, Kong), ensure `UVICORN_TIMEOUT_KEEP_ALIVE` is slightly higher than the proxy's idle timeout. This prevents race conditions where the proxy routes a request just as the worker shuts down the connection.

#### Example Compose Configuration:

```yaml
services:
  api:
    image: dartfx/docker-api-base:latest
    ports:
      - "8000:8000"
    environment:
      - WEB_CONCURRENCY=4
      - UVICORN_TIMEOUT_KEEP_ALIVE=15
      - UVICORN_PROXY_HEADERS=true
      - UVICORN_FORWARDED_ALLOW_IPS=*
```
