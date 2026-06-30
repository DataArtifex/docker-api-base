#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="dartfx/docker-api-base:latest"

echo "=== Verifying Docker Image: ${IMAGE_NAME} ==="

# 1. Check system utilities inherited from base
echo -n "Checking curl... "
docker run --rm "${IMAGE_NAME}" curl --version >/dev/null && echo "OK" || { echo "FAILED"; exit 1; }

echo -n "Checking jq... "
docker run --rm "${IMAGE_NAME}" jq --version >/dev/null && echo "OK" || { echo "FAILED"; exit 1; }

echo -n "Checking qsv... "
docker run --rm "${IMAGE_NAME}" qsv --version >/dev/null && echo "OK" || { echo "FAILED"; exit 1; }

# 2. Check Python package imports from base
echo "Checking base Python packages..."
BASE_PACKAGES=(
  "dartfx.utils"
)

for pkg in "${BASE_PACKAGES[@]}"; do
  echo -n "  - Importing ${pkg}... "
  docker run --rm "${IMAGE_NAME}" python -c "import ${pkg}" >/dev/null 2>&1 && echo "OK" || { echo "FAILED"; exit 1; }
done

# 3. Check new Python packages for FastAPI / uvicorn
echo "Checking API Python packages..."
API_PACKAGES=(
  "fastapi"
  "uvicorn"
)

for pkg in "${API_PACKAGES[@]}"; do
  echo -n "  - Importing ${pkg}... "
  docker run --rm "${IMAGE_NAME}" python -c "import ${pkg}" >/dev/null 2>&1 && echo "OK" || { echo "FAILED"; exit 1; }
done

# 4. Check that the container starts up and serves the mock API
echo -n "Checking API HTTP endpoint... "
CONTAINER_NAME="api-verify-temp"
TEST_PORT=8099

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Run in background with mapped port
docker run -d --name "${CONTAINER_NAME}" -p "${TEST_PORT}":8000 "${IMAGE_NAME}" >/dev/null

MAX_ATTEMPTS=20
ATTEMPT=0
SUCCESS=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if RESPONSE=$(curl -s --fail "http://localhost:${TEST_PORT}/" 2>/dev/null); then
    if echo "$RESPONSE" | grep -q "Data Artifex API Base is running"; then
      SUCCESS=true
      break
    fi
  fi
  ATTEMPT=$((ATTEMPT + 1))
  sleep 0.5
done

if [ "$SUCCESS" = true ]; then
  echo "OK"
else
  echo "FAILED"
  echo "=== Container logs ==="
  docker logs "${CONTAINER_NAME}"
  exit 1
fi

echo "=== All checks passed successfully! ==="
