#!/usr/bin/env bash
# Installs the monitoring stack into the current kubectl context:
#   - kube-prometheus-stack (Prometheus Operator, Prometheus, Alertmanager,
#     Grafana, node-exporter, kube-state-metrics) via Helm
#   - the TODO ServiceMonitor, alert rules and Grafana dashboard
#
# Environment:
#   GRAFANA_ADMIN_PASSWORD  Grafana admin password      (default: random, printed once)
#   CHART_VERSION           kube-prometheus-stack chart (default: pinned below)
#   MONITORING_NAMESPACE    namespace to install into   (default: observability)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${MONITORING_NAMESPACE:-observability}"
RELEASE="kube-prometheus-stack"
CHART_VERSION="${CHART_VERSION:-93.2.2}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if ! kubectl -n "${NAMESPACE}" get secret grafana-admin >/dev/null 2>&1; then
  generated=""
  if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
    generated="$(openssl rand -base64 18)"
  fi
  kubectl -n "${NAMESPACE}" create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-file=admin-password=<(printf '%s' "${GRAFANA_ADMIN_PASSWORD:-${generated}}") >/dev/null
  if [[ -n "${generated}" ]]; then
    echo "Generated Grafana admin password. Read it with:"
    echo "  kubectl -n ${NAMESPACE} get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d"
  fi
fi

echo "==> Installing ${RELEASE} ${CHART_VERSION}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null
helm upgrade --install "${RELEASE}" prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${ROOT_DIR}/monitoring/kubernetes/values.yaml" \
  --wait --timeout 10m

echo "==> Applying ServiceMonitor, alert rules and dashboard"
kubectl apply -k "${ROOT_DIR}/monitoring"

cat <<EOF

Monitoring is running:

  kubectl -n ${NAMESPACE} port-forward svc/${RELEASE}-grafana 3001:80          ->  http://localhost:3001  (dashboard: TODO / TODO Backend)
  kubectl -n ${NAMESPACE} port-forward svc/${RELEASE}-prometheus 9090:9090     ->  http://localhost:9090
EOF
