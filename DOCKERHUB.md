# dartfx/docker-api-base

`dartfx/docker-api-base` is the official API base Docker image for the **Data Artifex** platform. It extends the minimal `dartfx/docker-base` image to provide a secure, high-performance environment optimized for hosting FastAPI applications running with Uvicorn.

## Key Features

* **Python Virtual Environment**: Ready-to-use virtual environment located at `/opt/venv` (pre-configured in the `PATH`).
* **Package Manager**: Built-in support for [`uv`](https://github.com/astral-sh/uv) and Hatch for fast, reproducible dependency syncing.
* **FastAPI & Uvicorn**: Pre-installed FastAPI and Uvicorn (`uvicorn[standard]`) dependencies.
* **Security Defaults**:
  * Runs under a non-privileged system user: **`appuser`** (UID `10001`, GID `10001`).
  * Optimized for read-only root filesystems (`--read-only`).
  * Standard port `8000` exposed for API traffic.

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
