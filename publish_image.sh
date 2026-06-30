#!/usr/bin/env bash
set -euo pipefail

# Default configuration
DEFAULT_REGISTRY="docker.io"  # Docker Hub
DEFAULT_NAMESPACE="dartfx"
IMAGE_NAME="docker-api-base"
LOCAL_IMAGE="dartfx/docker-api-base:latest"

# Helper for showing usage
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -n, --namespace <name>  Docker Hub namespace/username (default: $DEFAULT_NAMESPACE)"
  echo "  -t, --tag <tag>          Additional custom tag to push"
  echo "  -r, --registry <url>     Target container registry (default: $DEFAULT_REGISTRY)"
  echo "  -s, --skip-verification  Skip running verify_image.sh before pushing"
  echo "  -f, --rebuild, --force   Force a clean rebuild with --no-cache"
  echo "  -h, --help               Show this help message"
  exit "${1:-1}"
}

# Parse arguments
NAMESPACE="$DEFAULT_NAMESPACE"
CUSTOM_TAG=""
REGISTRY="$DEFAULT_REGISTRY"
SKIP_VERIFICATION=false
REBUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -t|--tag)
      CUSTOM_TAG="$2"
      shift 2
      ;;
    -r|--registry)
      REGISTRY="$2"
      shift 2
      ;;
    -s|--skip-verification)
      SKIP_VERIFICATION=true
      shift
      ;;
    -f|--rebuild|--force)
      REBUILD=true
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown option: $1"
      usage 1
      ;;
  esac
done

# 1. Build/rebuild the local image
if [ "$REBUILD" = true ]; then
  echo "=== Rebuilding the image from scratch ==="
  echo "Performing a clean build of ${LOCAL_IMAGE}..."
  docker build --pull --no-cache -t "${LOCAL_IMAGE}" .
else
  echo "=== Ensuring the image is built and up-to-date ==="
  echo "Building ${LOCAL_IMAGE} (pulling base image if updated)..."
  docker build --pull -t "${LOCAL_IMAGE}" .
fi

# 2. Verify image first (unless skipped)
if [ "$SKIP_VERIFICATION" = false ]; then
  echo "=== Step 1: Verifying the image locally ==="
  if [ -f "./verify_image.sh" ]; then
    ./verify_image.sh
  else
    echo "Warning: verify_image.sh not found. Skipping verification."
  fi
  echo ""
fi

# 3. Extract version from pyproject.toml
VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' pyproject.toml | tr -d '[:space:]')
if [ -z "$VERSION" ]; then
  echo "Warning: Could not extract version from pyproject.toml"
  VERSION="0.1.0"  # Fallback
fi

# Determine tags to push
TAGS=("latest" "$VERSION")
if [ -n "$CUSTOM_TAG" ]; then
  TAGS+=("$CUSTOM_TAG")
fi

# 4. Prompt / instructions for authentication
echo "=== Step 2: Target Registry Information ==="
echo "Preparing to push to registry: ${REGISTRY}/${NAMESPACE}"
echo "Make sure you are logged in to the target registry."
echo "E.g.: docker login ${REGISTRY}"
echo ""

# 5. Tag and push images
echo "=== Step 3: Tagging and pushing images ==="
for tag in "${TAGS[@]}"; do
  # Determine full remote image name
  if [ "$REGISTRY" = "docker.io" ]; then
    REMOTE_IMAGE="${NAMESPACE}/${IMAGE_NAME}:${tag}"
  else
    REMOTE_IMAGE="${REGISTRY}/${NAMESPACE}/${IMAGE_NAME}:${tag}"
  fi
  
  echo "Tagging ${LOCAL_IMAGE} as ${REMOTE_IMAGE}..."
  docker tag "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"
  
  echo "Pushing ${REMOTE_IMAGE}..."
  docker push "${REMOTE_IMAGE}"
  echo "Successfully pushed ${REMOTE_IMAGE}"
  echo ""
done

echo "=== Successfully published all tags! ==="

if [ "$REGISTRY" = "docker.io" ]; then
  echo ""
  echo "Tip: You can update your Docker Hub repository description by copying the contents of DOCKERHUB.md"
  echo "     to the repository overview settings page at:"
  echo "     https://hub.docker.com/r/${NAMESPACE}/${IMAGE_NAME}"
fi
