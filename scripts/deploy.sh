#!/usr/bin/env bash
# Deploys the application to the current kubectl context and waits for the
# rollout. If a Deployment does not become healthy it is rolled back to its
# previous revision and the script exits non-zero.
#
# Usage: scripts/deploy.sh <overlay>           overlay: local | production
#
# Environment:
#   IMAGE_REGISTRY   registry path of the images, e.g. ghcr.io/my-user
#   IMAGE_TAG        immutable tag to deploy (required for `production`)
#   NAMESPACE        target namespace                  (default: todo)
#   ROLLOUT_TIMEOUT  per-workload rollout timeout      (default: 180s)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="${1:-local}"
NAMESPACE="${NAMESPACE:-todo}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"
OVERLAY_DIR="${ROOT_DIR}/k8s/overlays/${OVERLAY}"

if [[ ! -d "${OVERLAY_DIR}" ]]; then
  echo "Unknown overlay '${OVERLAY}' (expected: local or production)" >&2
  exit 2
fi

target="${OVERLAY_DIR}"
if [[ -n "${IMAGE_TAG:-}" ]]; then
  : "${IMAGE_REGISTRY:?IMAGE_REGISTRY must be set together with IMAGE_TAG}"
  # Pin the exact images of this release in a generated kustomization that
  # wraps the overlay, so the files tracked in Git are never modified.
  target="${ROOT_DIR}/.deploy"
  mkdir -p "${target}"
  cat > "${target}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../k8s/overlays/${OVERLAY}
images:
  - name: todo-backend
    newName: ${IMAGE_REGISTRY}/todo-backend
    newTag: "${IMAGE_TAG}"
  - name: todo-frontend
    newName: ${IMAGE_REGISTRY}/todo-frontend
    newTag: "${IMAGE_TAG}"
EOF
elif [[ "${OVERLAY}" == "production" ]]; then
  echo "IMAGE_REGISTRY and IMAGE_TAG are required for the production overlay" >&2
  exit 2
fi

echo "==> Context: $(kubectl config current-context)  overlay: ${OVERLAY}  tag: ${IMAGE_TAG:-local}"

echo "==> Ensuring secrets"
NAMESPACE="${NAMESPACE}" "${ROOT_DIR}/scripts/ensure-secrets.sh"

echo "==> Applying manifests"
kubectl apply -k "${target}"

diagnostics() {
  echo "---- pods ----"
  kubectl -n "${NAMESPACE}" get pods -o wide || true
  echo "---- recent events ----"
  kubectl -n "${NAMESPACE}" get events --sort-by=.lastTimestamp | tail -n 25 || true
  echo "---- logs: $1 ----"
  kubectl -n "${NAMESPACE}" logs "$1" --all-containers --tail=40 || true
}

echo "==> Waiting for the database"
if ! kubectl -n "${NAMESPACE}" rollout status statefulset/postgres --timeout="${ROLLOUT_TIMEOUT}"; then
  diagnostics statefulset/postgres
  exit 1
fi

failed=0
for deployment in backend frontend; do
  echo "==> Waiting for ${deployment}"
  if kubectl -n "${NAMESPACE}" rollout status "deployment/${deployment}" --timeout="${ROLLOUT_TIMEOUT}"; then
    continue
  fi

  failed=1
  diagnostics "deployment/${deployment}"
  revision="$(kubectl -n "${NAMESPACE}" get "deployment/${deployment}" \
    -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
  if [[ "${revision:-1}" -gt 1 ]]; then
    echo "==> Rolling ${deployment} back to the previous revision"
    kubectl -n "${NAMESPACE}" rollout undo "deployment/${deployment}"
    kubectl -n "${NAMESPACE}" rollout status "deployment/${deployment}" --timeout="${ROLLOUT_TIMEOUT}" || true
  fi
done

if [[ "${failed}" -ne 0 ]]; then
  echo "Deployment failed" >&2
  exit 1
fi

echo "==> Deployed"
kubectl -n "${NAMESPACE}" get deployments,statefulsets,pods
