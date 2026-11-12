#!/usr/bin/env bash
# Creates the Kubernetes Secrets the application needs. Secrets are never
# stored in Git: values come from the environment (CI secrets) or, for the
# database password on a fresh cluster, are generated randomly.
#
# Environment:
#   NAMESPACE          target namespace                       (default: todo)
#   DB_USER            database user                          (default: todo)
#   DB_PASSWORD        database password                      (default: random)
#   REGISTRY           image registry host                    (default: ghcr.io)
#   REGISTRY_USERNAME  } optional: when both are set, an image pull secret
#   REGISTRY_TOKEN     } named `registry-credentials` is created/updated
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-todo}"
DB_SECRET="todo-db-credentials"

# The namespace must exist before a Secret can be created in it.
kubectl apply -f "${ROOT_DIR}/k8s/base/namespace.yaml" >/dev/null

if kubectl -n "${NAMESPACE}" get secret "${DB_SECRET}" >/dev/null 2>&1; then
  # Never rotated implicitly: Postgres only reads the password when it
  # initialises its data directory, so a new value would lock the API out.
  echo "Secret ${DB_SECRET} already exists - leaving it untouched"
else
  password="${DB_PASSWORD:-$(openssl rand -hex 24)}"
  # The password is passed through a file descriptor, not argv, so it does not
  # show up in the process list.
  kubectl -n "${NAMESPACE}" create secret generic "${DB_SECRET}" \
    --from-literal=username="${DB_USER:-todo}" \
    --from-file=password=<(printf '%s' "${password}") >/dev/null
  echo "Secret ${DB_SECRET} created"
fi

if [[ -n "${REGISTRY_USERNAME:-}" && -n "${REGISTRY_TOKEN:-}" ]]; then
  kubectl -n "${NAMESPACE}" create secret docker-registry registry-credentials \
    --docker-server="${REGISTRY:-ghcr.io}" \
    --docker-username="${REGISTRY_USERNAME}" \
    --docker-password="${REGISTRY_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "Secret registry-credentials applied"
fi
