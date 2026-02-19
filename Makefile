.PHONY: help build test scan deploy clean install

# Zmienne
DOCKER_REGISTRY ?= localhost:5000
IMAGE_TAG ?= latest
NAMESPACE ?= autohealkube

help: ## Wyświetla pomoc
	@echo "AutoHealKube - Makefile"
	@echo ""
	@echo "Dostępne komendy:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Instaluje zależności Helm
	@echo "📦 Instalowanie zależności Helm..."
	cd helm/platform && helm dependency update

build: ## Buduje obrazy Docker
	@echo "🐳 Budowanie obrazów Docker..."
	docker build -t $(DOCKER_REGISTRY)/vulnerable-app:$(IMAGE_TAG) docker/vulnerable-app/
	docker build -t $(DOCKER_REGISTRY)/auto-heal-webhook:$(IMAGE_TAG) python/

build-local: ## Buduje obrazy Docker dla lokalnego użycia
	@echo "🐳 Budowanie obrazów Docker (lokalne)..."
	docker build -t vulnerable-app:latest docker/vulnerable-app/
	docker build -t auto-heal-webhook:latest python/

scan: ## Skanuje obrazy i kod pod kątem podatności (Trivy)
	@echo "🔍 Skanowanie podatności..."
	trivy image vulnerable-app:latest
	trivy image auto-heal-webhook:latest
	trivy fs --config trivy/trivy.yaml .

scan-config: ## Skanuje konfigurację Docker/Kubernetes
	@echo "🔍 Skanowanie konfiguracji..."
	trivy config docker/
	trivy k8s cluster --namespace $(NAMESPACE)

lint: ## Lintuje Helm charts
	@echo "🔍 Lintowanie Helm charts..."
	helm lint helm/platform/
	helm template helm/platform/ --debug

test: ## Uruchamia testy
	@echo "🧪 Uruchamianie testów..."
	@echo "Testowanie polityk Kyverno..."
	@for policy in kyverno/policies/**/*.yaml; do \
		echo "Testing $$policy"; \
		kyverno test $$policy || true; \
	done

deploy: install ## Deployuje platformę do Kubernetes
	@echo "🚀 Deployowanie platformy..."
	@if ! kubectl get namespace $(NAMESPACE) &>/dev/null; then \
		echo "📦 Tworzenie namespace $(NAMESPACE)..."; \
		kubectl create namespace $(NAMESPACE); \
	fi
	@echo "📝 Dodawanie etykiet Helm do namespace..."
	@kubectl label namespace $(NAMESPACE) app.kubernetes.io/managed-by=Helm --overwrite || true
	@kubectl annotate namespace $(NAMESPACE) meta.helm.sh/release-name=platform --overwrite || true
	@kubectl annotate namespace $(NAMESPACE) meta.helm.sh/release-namespace=$(NAMESPACE) --overwrite || true
	helm upgrade --install platform helm/platform/ \
		--namespace $(NAMESPACE) \
		--set loki-stack.promtail.config.clients[0].url=http://platform-loki.$(NAMESPACE).svc.cluster.local:3100/loki/api/v1/push \
		--set falco.enabled=false \
		--wait \
		--timeout 10m

deploy-local: build-local install ## Deployuje platformę lokalnie
	@echo "🚀 Deployowanie platformy lokalnie..."
	@if command -v minikube >/dev/null 2>&1 && minikube status &> /dev/null; then \
		echo "📥 Ładowanie obrazów do minikube..."; \
		minikube image load vulnerable-app:latest; \
		minikube image load auto-heal-webhook:latest; \
	fi
	@if ! kubectl get namespace $(NAMESPACE) &>/dev/null; then \
		echo "📦 Tworzenie namespace $(NAMESPACE)..."; \
		kubectl create namespace $(NAMESPACE); \
	fi
	@echo "📝 Dodawanie etykiet Helm do namespace..."
	@kubectl label namespace $(NAMESPACE) app.kubernetes.io/managed-by=Helm --overwrite || true
	@kubectl annotate namespace $(NAMESPACE) meta.helm.sh/release-name=platform --overwrite || true
	@kubectl annotate namespace $(NAMESPACE) meta.helm.sh/release-namespace=$(NAMESPACE) --overwrite || true
	helm upgrade --install platform helm/platform/ \
		--namespace $(NAMESPACE) \
		--set demoApp.image=vulnerable-app:latest \
		--set autoHealWebhook.image=auto-heal-webhook:latest \
		--set loki-stack.promtail.config.clients[0].url=http://platform-loki.$(NAMESPACE).svc.cluster.local:3100/loki/api/v1/push \
		--set falco.enabled=false \
		--wait \
		--timeout 10m

apply-kyverno: ## Stosuje polityki Kyverno
	@echo "🛡️ Stosowanie polityk Kyverno..."
	kubectl apply -f kyverno/policies/best-practices/
	kubectl apply -f kyverno/policies/security/
	kubectl apply -f kyverno/policies/test/

apply-falco: ## Konfiguruje Falco z custom rules
	@echo "👁️ Konfiguracja Falco..."
	kubectl create configmap falco-custom-rules \
		--from-file=falco/rules/custom-rules.yaml \
		--namespace $(NAMESPACE) \
		--dry-run=client -o yaml | kubectl apply -f -

status: ## Sprawdza status zasobów
	@echo "📊 Status zasobów w namespace $(NAMESPACE):"
	@kubectl get pods -n $(NAMESPACE)
	@kubectl get svc -n $(NAMESPACE)
	@kubectl get deployments -n $(NAMESPACE)

logs: ## Wyświetla logi auto-heal webhook
	@kubectl logs -n $(NAMESPACE) -l app=auto-heal-webhook -f

logs-falco: ## Wyświetla logi Falco
	@kubectl logs -n $(NAMESPACE) -l app=falco -f

clean: ## Usuwa zasoby z Kubernetes
	@echo "🧹 Czyszczenie zasobów..."
	helm uninstall platform --namespace $(NAMESPACE) || true
	kubectl delete namespace $(NAMESPACE) || true

clean-all: clean ## Usuwa wszystkie zasoby i obrazy
	@echo "🧹 Usuwanie obrazów Docker..."
	docker rmi vulnerable-app:latest auto-heal-webhook:latest || true

start: deploy-local apply-kyverno apply-falco ## Uruchamia całą platformę lokalnie (alias dla start-local.sh)
	@bash scripts/start-local.sh
