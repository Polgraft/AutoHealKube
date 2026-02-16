# Makefile dla AutoHealKube - Automatyzacja komend (setup, scan, deploy)
# Użyj: make <target> (np. make setup)
# Zależności: Git, Ansible, Helm, Terraform, etc. (instalowane via Ansible)
# Wersje z values.yaml (użyj yq do parsowania, jeśli potrzeba - zakładam zainstalowane)

# Defaults / Zmienne
KUBE_VERSION ?= $(shell yq '.kubernetesVersion' values.yaml | tr -d '"')  # Pobierz z values.yaml (kompatybilne z yq z apt)
ENV ?= dev
IMAGE_NAME ?= $(shell yq '.imageName' values.yaml | tr -d '"')

# Help: Wyświetl dostępne targety
help:
	@echo "Dostępne komendy:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Automatyzacja setupu (call Ansible: instal deps, config env)
	@echo "Uruchamiam setup via Ansible..."
	ansible-playbook ansible/setup.yml -e "env=$(ENV)"

scan: ## Skanuj obrazy/manifesty via Trivy (block HIGH/CRITICAL)
	@echo "Skanuję obraz: $(IMAGE_NAME)"
	trivy image --exit-code 1 --severity $(shell yq '.trivy.severityBlock' values.yaml | tr -d '"') $(IMAGE_NAME)
	@echo "Skanuję manifesty (np. core/manifests)..."
	trivy fs --exit-code 1 --severity $(shell yq '.trivy.severityBlock' values.yaml | tr -d '"') core/manifests/
	@echo "Skanuję IaC (Terraform)..."
	trivy config --exit-code 1 --severity $(shell yq '.trivy.severityBlock' values.yaml | tr -d '"') infra/

deploy-local: ## Deploy lokalnie (Minikube + Helm install tools)
	@echo "Start Minikube..."
	minikube start --kubernetes-version=$(KUBE_VERSION)
	@echo "Instaluj tools via Helm (Falco, Kyverno, etc.)..."
	helm repo add falco https://falcosecurity.github.io/charts
	helm install falco falco/falco --version $(shell yq '.falco.version' values.yaml | tr -d '"') --set driver.kind=modern_ebpf
	helm repo add kyverno https://kyverno.github.io/kyverno/
	helm install kyverno kyverno/kyverno --version $(shell yq '.kyverno.version' values.yaml | tr -d '"')
	# Dodaj więcej: ArgoCD, Prometheus, Loki, etc. - rozszerzymy później
	@echo "Deploy core manifests..."
	kubectl apply -f core/manifests/

deploy-cloud: ## Deploy do GCP (Terraform init/apply + ArgoCD sync)
	@echo "Inicjuj Terraform dla GCP..."
	cd infra && terraform init
	cd infra && terraform apply -auto-approve -var="project_id=$(shell yq '.gcp.projectId' values.yaml | tr -d '\"')" -var="region=$(shell yq '.gcp.region' values.yaml | tr -d '\"')"
	@echo "Konfiguruj kubectl do GKE..."
	gcloud container clusters get-credentials autohealkube-cluster --zone $(shell yq '.gcp.region' values.yaml | tr -d '"')-a --project $(shell yq '.gcp.projectId' values.yaml | tr -d '"')
	@echo "Deploy ArgoCD i sync..."
	helm repo add argo https://argoproj.github.io/argo-helm
	helm install argocd argo/argocd --version $(shell yq '.argocd.version' values.yaml | tr -d '"')
	kubectl apply -f core/  # Przykładowo - sync manifestów via Argo później

clean: ## Czyszczenie (usuwanie Minikube, etc.)
	minikube delete
	rm -rf infra/.terraform/

.PHONY: help setup scan deploy-local deploy-cloud clean

deploy-cloud: ## Deploy do GCP (Terraform init/apply + ArgoCD sync)
	@echo "Inicjuj Terraform dla GCP..."
	cd infra && terraform init
	cd infra && terraform apply -auto-approve -var="project_id=$(shell yq '.gcp.projectId' ../values.yaml | tr -d '\"')" -var="region=$(shell yq '.gcp.region' ../values.yaml | tr -d '\"')" -var="gke_version=$(shell yq '.gcp.gkeVersion' ../values.yaml | tr -d '\"')"
	@echo "Konfiguruj kubectl do GKE..."
	gcloud container clusters get-credentials autohealkube-cluster --zone $(shell yq '.gcp.region' ../values.yaml | tr -d '"')-a --project $(shell yq '.gcp.projectId' ../values.yaml | tr -d '"')
	@echo "Deploy tools via Helm na GKE..."
	# Security core
	helm upgrade --install falco falco/falco --repo https://falcosecurity.github.io/charts --version $(shell yq '.falco.version' values.yaml | tr -d '"') --set driver.kind=modern_ebpf --namespace falco --create-namespace
	helm upgrade --install kyverno kyverno/kyverno --repo https://kyverno.github.io/kyverno/ --version $(shell yq '.kyverno.version' values.yaml | tr -d '"') --namespace kyverno --create-namespace
	# GitOps
	helm upgrade --install argocd argo/argo-cd --repo https://argoproj.github.io/argo-helm --version $(shell yq '.argocd.version' values.yaml | tr -d '"') --namespace argocd --create-namespace
	# Monitoring
	helm upgrade --install prometheus prometheus-community/prometheus --repo https://prometheus-community.github.io/helm-charts --version $(shell yq '.prometheus.version' values.yaml | tr -d '"') --namespace monitoring --create-namespace
	helm upgrade --install loki grafana/loki --repo https://grafana.github.io/helm-charts --version $(shell yq '.loki.version' values.yaml | tr -d '"') --namespace monitoring --create-namespace
	helm upgrade --install grafana grafana/grafana --repo https://grafana.github.io/helm-charts --version 7.3.0 --namespace monitoring --create-namespace  # Dostosuj wersję
	@echo "Apply custom configs (policies, falco-output)..."
	kubectl apply -f core/policies/
	kubectl apply -f core/monitoring/prometheus.yml
	@echo "Deploy webhook i dashboard (images z GHCR via pipeline)..."
	kubectl apply -f core/manifests/webhook-deployment.yaml
	kubectl apply -f core/manifests/dashboard-deployment.yaml
	@echo "Konfiguruj Falco output do webhook (service URL w chmurze)..."
	helm upgrade falco falco/falco --set http_output.enabled=true --set http_output.url=$(shell yq '.webhook.url' values.yaml | tr -d '"') --namespace falco
	kubectl rollout restart daemonset/falco -n falco
	@echo "Sync via ArgoCD..."
	argocd app sync autohealkube-core  # Zakładaj ArgoCD CLI