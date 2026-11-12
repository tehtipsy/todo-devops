# Shortcuts for the most common tasks. Run `make` to list them.

APP_REPO_PATH ?= ../todo-app
LOCAL_URL     ?= http://localhost:8080

.DEFAULT_GOAL := help
.PHONY: help up up-monitoring down logs build test k8s-up k8s-deploy k8s-forward k8s-monitoring k8s-down smoke validate

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Docker Compose ------------------------------------------------------------

up: ## Build and start the app with Docker Compose (http://localhost:8080)
	docker compose up --build -d

up-monitoring: ## Same, plus Prometheus (:9090) and Grafana (:3001)
	docker compose --profile monitoring up --build -d

down: ## Stop the Docker Compose environment (data volumes are kept)
	docker compose --profile monitoring down

logs: ## Follow the application logs
	docker compose logs -f backend frontend

# --- Images --------------------------------------------------------------------

build: ## Build both images, tagged :local
	APP_REPO_PATH=$(APP_REPO_PATH) scripts/build-images.sh local

test: ## Run backend lint + tests inside the Docker build (test stage)
	docker buildx build --build-context app=$(APP_REPO_PATH) --target test docker/backend

# --- Kubernetes ----------------------------------------------------------------

k8s-up: ## Start minikube, build + load the images, deploy
	APP_REPO_PATH=$(APP_REPO_PATH) scripts/local-up.sh

k8s-deploy: ## Apply the local overlay to the current cluster
	scripts/deploy.sh local

k8s-forward: ## Forward the frontend Service to http://localhost:8080
	kubectl -n todo port-forward svc/frontend 8080:80

k8s-monitoring: ## Install Prometheus + Grafana and the TODO dashboard
	scripts/monitoring-up.sh

k8s-down: ## Remove the application from the cluster (deletes its data)
	kubectl delete namespace todo

# --- Checks --------------------------------------------------------------------

smoke: ## End-to-end smoke test against LOCAL_URL
	scripts/smoke-test.sh $(LOCAL_URL)

validate: ## Render all Kubernetes manifests (catches YAML and kustomize errors)
	kubectl kustomize k8s/overlays/local > /dev/null
	kubectl kustomize k8s/overlays/production > /dev/null
	kubectl kustomize monitoring > /dev/null
	@echo "manifests render cleanly"
