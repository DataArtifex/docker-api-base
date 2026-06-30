# --- Stage 1: Build & Sync Environment (Python Packages Only) ---
FROM dartfx/docker-base:latest AS builder

WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv
COPY pyproject.toml ./

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The base image already has /opt/venv. We will sync and install the new FastAPI/uvicorn dependencies.
ENV PATH="/opt/venv/bin:$PATH"
RUN uv pip install .

# --- Stage 2: Final Published API Runtime ---
FROM dartfx/docker-base:latest

WORKDIR /app

# Copy the updated virtual environment from the builder stage
COPY --from=builder --chown=appuser:appgroup /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy the default mock main.py API
COPY --chown=appuser:appgroup main.py ./

# Expose default FastAPI/uvicorn port
EXPOSE 8000

# Switch to the non-privileged user
USER appuser

# Default command (can be overridden by child images)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
