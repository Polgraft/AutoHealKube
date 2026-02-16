# Makefile dla AutoHealKube - Automatyzacja komend (setup, scan, deploy)
# Użyj: make <target> (np. make setup)
# Zależności: Git, Ansible, Helm, Terraform, etc. (instalowane via Ansible)
# Wersje z values.yaml (użyj yq do parsowania, jeśli potrzeba - zakładam zainstalowane)

# Defaults / Zmienne
KUBE_VERSION ?= $(shell yq e '.kubernetesVersion' values.yaml)  # Pobierz z values.yaml (zainstaluj yq jeśli brak: brew install yq)
ENV ?= dev
IMAGE_NAME ?= $(shell yq e '.imageName' values.yaml)

# Help: Wyświetl dostępne targety
help:
	@echo "Dostępne komendy:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Automatyzacja setupu (call Ansible: instal deps, config env)
	@echo "Uruchamiam setup via Ansible..."
	ansible-playbook ansible/setup.yml -e "env=$(ENV)"

scan: ## Skanuj obrazy/manifesty via Trivy (block HIGH/CRITICAL)
	@echo "Skanuję obraz: $(IMAGE_NAME)"
	trivy image --exit-code 1 --severity $(shell yq e '.trivy.severityBlock' values.yaml) $(IMAGE_NAME)
	@echo "Skanuję manifesty (np. core/manifests)..."
	trivy fs --exit-code 1 --severity $(shell yq e '.trivy.severityBlock' values.yaml) core/manifests/
	@echo "Skanuję IaC (Terraform)..."
	trivy config --exit-code 1 --severity $(shell yq e '.trivy.severityBlock' values.yaml) infra/

deploy-local: ## Deploy lokalnie (Minikube + Helm install tools)
	@echo "Start Minikube..."
	minikube start --kubernetes-version=$(KUBE_VERSION)
	@echo "Instaluj tools via Helm (Falco, Kyverno, etc.)..."
	helm repo add falco https://falcosecurity.github.io/charts
	helm install falco falco/falco --version $(shell yq e '.falco.version' values.yaml) --set driver.kind=modern_ebpf
	helm repo add kyverno https://kyverno.github.io/kyverno/
	helm install kyverno kyverno/kyverno --version $(shell yq e '.kyverno.version' values.yaml)
	# Dodaj więcej: ArgoCD, Prometheus, Loki, etc. - rozszerzymy później
	@echo "Deploy core manifests..."
	kubectl apply -f core/manifests/

deploy-cloud: ## Deploy do GCP (Terraform init/apply + ArgoCD sync)
	@echo "Inicjuj Terraform dla GCP..."
	cd infra && terraform init
	cd infra && terraform apply -auto-approve -var="project_id=$(shell yq e '.gcp.projectId' values.yaml)" -var="region=$(shell yq e '.gcp.region' values.yaml)"
	@echo "Konfiguruj kubectl do GKE..."
	gcloud container clusters get-credentials autohealkube-cluster --zone $(shell yq e '.gcp.region' values.yaml)-a --project $(shell yq e '.gcp.projectId' values.yaml)
	@echo "Deploy ArgoCD i sync..."
	helm repo add argo https://argoproj.github.io/argo-helm
	helm install argocd argo/argocd --version $(shell yq e '.argocd.version' values.yaml)
	kubectl apply -f core/  # Przykładowo - sync manifestów via Argo później

clean: ## Czyszczenie (usuwanie Minikube, etc.)
	minikube delete
	rm -rf infra/.terraform/

.PHONY: help setup scan deploy-local deploy-cloud clean