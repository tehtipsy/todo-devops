#!/usr/bin/env bash
# One command from zero to a running application on a local minikube cluster:
# starts minikube, builds the images, loads them into the cluster and deploys
# the `local` overlay.
#
# Environment:
#   APP_REPO_PATH     path to the application repository  (default: ../todo-app)
#   MINIKUBE_PROFILE  minikube profile to use             (default: minikube)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${MINIKUBE_PROFILE:-minikube}"

for tool in docker kubectl minikube; do
  command -v "${tool}" >/dev/null || { echo "Missing required tool: ${tool}" >&2; exit 1; }
done

if ! minikube -p "${PROFILE}" status >/dev/null 2>&1; then
  echo "==> Starting minikube (${PROFILE})"
  minikube -p "${PROFILE}" start --cpus=2 --memory=4096
fi
kubectl config use-context "${PROFILE}" >/dev/null

echo "==> Enabling addons"
minikube -p "${PROFILE}" addons enable ingress >/dev/null
minikube -p "${PROFILE}" addons enable metrics-server >/dev/null

"${ROOT_DIR}/scripts/build-images.sh" local

echo "==> Loading images into the cluster"
minikube -p "${PROFILE}" image load todo-backend:local todo-frontend:local

"${ROOT_DIR}/scripts/deploy.sh" local

# The tag `local` is mutable, so an unchanged manifest would keep running the
# old image: restart the pods to pick up what was just loaded.
kubectl -n todo rollout restart deployment/backend deployment/frontend >/dev/null
kubectl -n todo rollout status deployment/backend --timeout=180s
kubectl -n todo rollout status deployment/frontend --timeout=180s

cat <<EOF

The application is running. Open it with either:

  kubectl -n todo port-forward svc/frontend 8080:80     ->  http://localhost:8080

  echo "\$(minikube -p ${PROFILE} ip) todo.local" | sudo tee -a /etc/hosts
                                                        ->  http://todo.local

Verify it end to end:  scripts/smoke-test.sh http://localhost:8080
EOF
