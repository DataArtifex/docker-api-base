# dartfx/docker-api-base

This repository contains the configuration for the API base Docker image used by the **Data Artifex** platform. This image extends `dartfx/docker-base` and adds the necessary components to host a FastAPI application running with uvicorn.

## Architecture & Structure

The Docker image is built using a multi-stage `Dockerfile`:

1. **Builder Stage**: Extends `dartfx/docker-base:latest` and updates the synchronized Python virtual environment using the [`uv`](https://github.com/astral-sh/uv) package manager. It installs FastAPI and uvicorn dependencies defined in `pyproject.toml`.
2. **Final Runtime Stage**: Extends `dartfx/docker-base:latest`, copies the updated Python virtual environment, copies a default mock `main.py` API (enabling out-of-the-box runnability), exposes port `8000`, and sets the default CMD to run uvicorn.

## Package Dependencies

This API base environment adds the following dependencies:
- `fastapi`
- `uvicorn` (with standard dependencies)

These dependencies are managed via `pyproject.toml` and synchronized into `/opt/venv` within the container.

## Production Security Guidelines

To run containers built from these images securely in production, follow these key recommendations:

### 1. Run as a Non-Root User (Default Setup)
By default, Docker containers run as root, which presents a significant security risk. To mitigate this:
* This image runs by default under a non-privileged system user: **`appuser`** (UID `10001`, GID `10001` under **`appgroup`**), which is pre-defined in the base image.
* **Inheritance & Build Design:** Creating the user at the base image level ensures consistent UID/GID settings across all services in your application stack (making shared volume permissions and cluster security rules simpler to manage). The base image leaves the active user as `root` to simplify build-time actions, but final deployable images (like this API base) switch to `USER appuser` at the end of the runtime stage.
* The default working directory (`/app`) and Python virtual environment (`/opt/venv`) are pre-configured with appropriate permissions.
* Downstream images extending this API base should make sure copied files are owned by the non-privileged user:
  ```dockerfile
  COPY --chown=appuser:appgroup . /app
  ```

### 2. Read-Only Root Filesystem
Configure your production orchestrator (e.g., Kubernetes or AWS ECS) to run containers with a read-only root filesystem (`readOnlyRootFilesystem: true` or `--read-only`). This prevents files from being modified or written to the container dynamically.
* If your API needs to write temporary files (e.g., file uploads, CSV exports), mount a `tmpfs` volume or directory at `/tmp`.

### 3. Build Reproducibility & Base Image Pinning
While `dartfx/docker-base:latest` is clean, the underlying package versions may change during rebuilds.
* In production-bound builds, pin the base image to specific tags or, ideally, to their SHA256 digest:
  ```dockerfile
  FROM dartfx/docker-base:latest@sha256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  ```

### 4. Secrets Management
Never hardcode or build secrets (API keys, database passwords, SSL/TLS certificates) into the Docker image layers.
* Inject all credentials at runtime using environment variables managed by a secrets provider (e.g., Kubernetes Secrets, AWS Secrets Manager, HashiCorp Vault).

### 5. Disable Development Features in Production
Ensure downstream applications:
* Do **not** use Uvicorn's `--reload` flag in production (increases resource overhead and security risks).
* Disable debug mode in FastAPI (`debug=False`).
* Adjust logging levels to avoid leaking sensitive data in production log streams.

### 6. Network & TLS Termination
Avoid exposing Uvicorn directly to the internet.
* Run Uvicorn behind a production-grade reverse proxy or ingress controller (such as Nginx, Traefik, AWS Application Load Balancer, or Cloudflare).
* Use the reverse proxy to terminate SSL/TLS, handle rate-limiting, filter requests, and manage client connections.

## Getting Started

### Building the Image

To build the Docker image locally, ensure you have first built the base image (`dartfx/docker-base:latest`) in the sibling directory, then run:

```bash
docker build -t dartfx/docker-api-base:latest .
```

### Verifying the Image

A script is provided to verify the image. It checks that system utilities (like `qsv`) remain available, verifies that Python packages (`fastapi`, `uvicorn`, `dartfx.utils`) are importable, and spins up a temporary container to confirm the mock API is successfully responding to HTTP requests on port 8099.

To run the verification checks:

```bash
./verify_image.sh
```

### Running the Image

You can run the built image locally to test the mock API endpoint:

```bash
docker run --rm -p 8000:8000 dartfx/docker-api-base:latest
```

Once running, you can access the mock API at `http://localhost:8000/`. For example, using `curl`:

```bash
curl http://localhost:8000/
```

Which will return:
```json
{"status":"ok","message":"Data Artifex API Base is running."}
```

### Entering the Container Shell

To debug or inspect the container environment, you can log into the container's shell.

#### Option A: Start a new container with an interactive shell
```bash
docker run --rm -it dartfx/docker-api-base:latest /bin/bash
```

#### Option B: Open a shell in an already running container
1. Find the running container's ID or name:
   ```bash
   docker ps
   ```
2. Exec into the container:
   ```bash
   docker exec -it <container_id_or_name> /bin/bash
   ```

### Publishing the Image

A utility script `publish_image.sh` is provided to automate tagging and pushing the image to Docker Hub (or another container registry). By default, the script:
1. Ensures the local image exists (builds it if not).
2. Verifies the image locally using `./verify_image.sh` to make sure all checks pass.
3. Extracts the version string from [pyproject.toml](file:///Users/pascal/Library/CloudStorage/Dropbox/git-dartfx/docker-api-base/pyproject.toml) (e.g. `0.1.0`).
4. Tags the image with both `latest` and the version tag.
5. Pushes the tagged images to the registry.

#### Prerequisites

Before running the script, ensure you are authenticated with Docker Hub (or your target container registry):

```bash
docker login
```

#### Usage Examples

To publish to the default namespace (`dartfx`):

```bash
./publish_image.sh
```

To publish to your own personal Docker Hub namespace or organization:

```bash
./publish_image.sh --namespace myusername
```

To push to an alternate registry (like GitHub Container Registry or AWS ECR):

```bash
./publish_image.sh --registry ghcr.io --namespace myorganization
```

#### Script Options

```
Options:
  -n, --namespace <name>  Docker Hub namespace/username (default: dartfx)
  -t, --tag <tag>          Additional custom tag to push
  -r, --registry <url>     Target container registry (default: docker.io)
  -s, --skip-verification  Skip running verify_image.sh before pushing
  -h, --help               Show usage help
```

## Usage in a FastAPI Project

All FastAPI projects extending this base image should use [hatch](https://hatch.pypa.io/) and [`uv`](https://github.com/astral-sh/uv), with project configurations and dependencies defined in a `pyproject.toml` file.

### 1. Project Structure

A typical project structure looks like this:

```
my-api-service/
├── Dockerfile
├── pyproject.toml
└── src/
    └── my_api_service/
        ├── __init__.py
        └── main.py
```

### 2. Project Configuration (`pyproject.toml`)

Define your project's dependencies and packaging configuration in `pyproject.toml`:

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my-api-service"
version = "0.1.0"
dependencies = [
    # Define additional python packages here.
    # Note: fastapi and uvicorn are inherited from the base image.
    "httpx",
]

[tool.hatch.metadata]
allow-direct-references = true

[tool.hatch.build.targets.wheel]
packages = ["src/my_api_service"]
```

### 3. Dockerfile Configuration

Use a multi-stage Dockerfile to build and sync your application dependencies using `uv` into the pre-existing virtual environment (`/opt/venv`):

```dockerfile
# --- Builder Stage ---
FROM dartfx/docker-api-base:latest AS builder
WORKDIR /app

# Install uv for fast package management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Copy project configuration files first to optimize layer caching
COPY pyproject.toml ./

# Install project dependencies from pyproject.toml into the virtual environment
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

# Override the CMD to point to your Hatch-installed package's entrypoint:
CMD ["uvicorn", "my_api_service.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 4. Building and Running

To build and run the Docker image:

```bash
docker build -t my-api-service .
docker run -p 8000:8000 my-api-service
```

## License

This project is licensed under the [MIT License](file:///Users/pascal/Library/CloudStorage/Dropbox/git-dartfx/docker-api-base/LICENSE).

