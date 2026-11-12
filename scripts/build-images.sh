#!/usr/bin/env bash
# Builds the backend and frontend images from the application repository.
#
# Usage: scripts/build-images.sh [tag]         (default tag: local)
#
# Environment:
#   APP_REPO_PATH   path to the application repository   (default: ../todo-app)
#   IMAGE_REGISTRY  optional prefix, e.g. ghcr.io/my-user
#   RUN_TESTS       "true" also builds the backend `test` stage (lint + tests)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-local}"
APP_REPO_PATH="$(cd "${APP_REPO_PATH:-${ROOT_DIR}/../todo-app}" && pwd)"
PREFIX="${IMAGE_REGISTRY:+${IMAGE_REGISTRY}/}"

if ! docker buildx version >/dev/null 2>&1; then
  echo "Docker BuildKit (buildx) is required: the Dockerfiles use a named build context." >&2
  echo "Install it with your package manager, e.g. 'sudo apt-get install docker-buildx'." >&2
  exit 1
fi

if [[ "${RUN_TESTS:-false}" == "true" ]]; then
  echo "==> Backend: lint + tests"
  docker buildx build --build-context "app=${APP_REPO_PATH}" --target test "${ROOT_DIR}/docker/backend"
fi

for component in backend frontend; do
  image="${PREFIX}todo-${component}:${TAG}"
  echo "==> Building ${image}"
  docker buildx build --load \
    --build-context "app=${APP_REPO_PATH}" \
    --tag "${image}" \
    "${ROOT_DIR}/docker/${component}"
done
