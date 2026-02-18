#!/bin/bash
# bootstrap/install-local.sh - Skrypt startowy dla lokalnego setupu AutoHealKube
# Call: ./install-local.sh [env=dev]
# Robi: Call Ansible setup, start Minikube, Helm install Security core (Falco, Kyverno), apply policies.
# Zależności: Makefile, values.yaml, Ansible zainstalowane.

# Defaults
ENV="${1:-dev}"  # Pierwszy arg: env (dev/default)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# Parsuj values.yaml (użyj yq - kompatybilne z wersją jq-style z apt)
KUBE_VERSION=$(yq '.kubernetesVersion' "$ROOT_DIR/values.yaml" | tr -d '"')
FALCO_VERSION=$(yq '.falco.version' "$ROOT_DIR/values.yaml" | tr -d '"')
KYVERNO_VERSION=$(yq '.kyverno.version' "$ROOT_DIR/values.yaml" | tr -d '"')
WEBHOOK_URL=$(yq '.webhook.url' "$ROOT_DIR/values.yaml" | tr -d '"')  # DODANE: Pobierz URL z values.yaml (dla reusable)

# Krok 1: Call Ansible setup (instal deps)
echo "Uruchamiam Ansible setup..."
make -C "$ROOT_DIR" setup ENV="$ENV"

# Krok 2: Start Minikube jeśli nie działa
if ! minikube status | grep -q "Running"; then
  echo "Startuję Minikube z wersją K8s $KUBE_VERSION..."
  minikube start --kubernetes-version="v$KUBE_VERSION"
fi

# Krok 3: Instaluj Security core via Helm
echo "Instaluję Falco (runtime detection)..."
helm install falco falcosecurity/falco \
  --version "$(yq e '.falco.chartVersion' "$ROOT_DIR/values.yaml")" \
  --repo https://falcosecurity.github.io/charts \
  --set driver.kind=modern_ebpf \
  --namespace falco --create-namespace

# DODANE: Krok 3.5: Apply custom Falco config (output do webhook)
echo "Aplicuję custom Falco output config..."
# Najpierw wygeneruj token i skonfiguruj auth end-to-end (Falco -> header -> webhook)
WEBHOOK_BEARER_TOKEN="$(openssl rand -hex 32)"
kubectl create secret generic remediation-webhook-auth \
  --from-literal=bearerToken="$WEBHOOK_BEARER_TOKEN" \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply ConfigMap (wstrzyknij URL + bearer token do header Authorization)
sed -e "s|__WEBHOOK_URL__|$WEBHOOK_URL|g" -e "s|__WEBHOOK_BEARER_TOKEN__|$WEBHOOK_BEARER_TOKEN|g" \
  "$ROOT_DIR/core/policies/falco-output.yaml" | kubectl apply -f -
# Update Helm z override (http_output)
helm upgrade --install falco falco \
  --repo https://falcosecurity.github.io/charts \
  --set driver.kind=modern_ebpf \
  --set http_output.enabled=true \
  --set http_output.url="$WEBHOOK_URL" \
  --set json_output=true \
  --namespace falco --create-namespace
# Restart Falco dla reload config
kubectl rollout restart daemonset/falco -n falco

echo "Instaluję Kyverno (policy enforcement)..."
helm upgrade --install kyverno kyverno \
  --repo https://kyverno.github.io/kyverno/ \
  --namespace kyverno --create-namespace

ARGOCD_VERSION=$(yq '.argocd.version' "$ROOT_DIR/values.yaml" | tr -d '"')
ARGOCD_REPO_URL=$(yq '.argocd.repoUrl' "$ROOT_DIR/values.yaml" | tr -d '"')
# DODANE: Krok 4: Instaluj ArgoCD (GitOps)
echo "Instaluję ArgoCD..."
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --namespace argocd --create-namespace

# Czekaj na ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Stwórz Application dla sync manifestów z Git
echo "Tworzę ArgoCD Application dla auto-sync..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: autohealkube-core
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "$ARGOCD_REPO_URL"
    targetRevision: HEAD
    path: core/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF




# Krok 4: Apply przykładowe policies (z core/policies)
echo "Aplicuję Kyverno policies..."
kubectl apply -f "$ROOT_DIR/core/policies/"

# DODANE: Krok 5: Build i deploy remediation webhook
echo "Buduję i deployuję remediation webhook..."
# Użyj pustej konfiguracji Docker, aby uniknąć docker-credential-desktop.exe pod WSL.
# Tworzymy tymczasową konfigurację zamiast trzymać `.docker-empty-config/` w repo.
EMPTY_DOCKER_CONFIG_DIR="$(mktemp -d)"
trap 'rm -rf "$EMPTY_DOCKER_CONFIG_DIR"' EXIT
echo '{}' > "$EMPTY_DOCKER_CONFIG_DIR/config.json"
DOCKER_CONFIG="$EMPTY_DOCKER_CONFIG_DIR" docker build -t autohealkube-webhook:latest "$ROOT_DIR/core/remediation-webhook/"
DOCKER_CONFIG="$EMPTY_DOCKER_CONFIG_DIR" minikube image load autohealkube-webhook:latest
kubectl apply -f "$ROOT_DIR/core/manifests/webhook-deployment.yaml"
# DODANE: Deploy HTMX dashboard
echo "Buduję i deployuję HTMX dashboard..."
DOCKER_CONFIG="$EMPTY_DOCKER_CONFIG_DIR" docker build -t autohealkube-dashboard:latest "$ROOT_DIR/core/dashboard/"
DOCKER_CONFIG="$EMPTY_DOCKER_CONFIG_DIR" minikube image load autohealkube-dashboard:latest
kubectl apply -f "$ROOT_DIR/core/manifests/dashboard-deployment.yaml"


# Krok 6: Weryfikacja (dawny krok 5, rozszerzony)
echo "Weryfikuję instalacje..."
helm list
kubectl get pods -n falco
kubectl get pods -n kyverno
kubectl get pods -l app=remediation-webhook  # DODANE: Sprawdź webhook
kubectl logs -n falco -l app.kubernetes.io/name=falco  # DODANE: Logs Falco dla config check

echo "Setup lokalny ukończony! Teraz możesz testować: make scan, kubectl apply -f core/manifests/"