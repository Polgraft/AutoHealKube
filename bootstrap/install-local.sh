#!/bin/bash
# bootstrap/install-local.sh - Skrypt startowy dla lokalnego setupu AutoHealKube
# Call: ./install-local.sh [env=dev]
# Robi: Call Ansible setup, start Minikube, Helm install Security core (Falco, Kyverno), apply policies.
# Zależności: Makefile, values.yaml, Ansible zainstalowane.

# Defaults
ENV="${1:-dev}"  # Pierwszy arg: env (dev/default)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# Parsuj values.yaml (użyj yq)
KUBE_VERSION=$(yq e '.kubernetesVersion' "$ROOT_DIR/values.yaml")
FALCO_VERSION=$(yq e '.falco.version' "$ROOT_DIR/values.yaml")
KYVERNO_VERSION=$(yq e '.kyverno.version' "$ROOT_DIR/values.yaml")
WEBHOOK_URL=$(yq e '.webhook.url' "$ROOT_DIR/values.yaml")  # DODANE: Pobierz URL z values.yaml (dla reusable)

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
helm upgrade --install falco falco/falco \
  --repo https://falcosecurity.github.io/charts \
  --version "$FALCO_VERSION" \
  --set driver.kind=modern_ebpf \
  --namespace falco --create-namespace

# DODANE: Krok 3.5: Apply custom Falco config (output do webhook)
echo "Aplicuję custom Falco output config..."
# Najpierw apply ConfigMap (zastąp placeholders z values.yaml)
sed "s|{{ .Values.webhook.url }}|$WEBHOOK_URL|g" "$ROOT_DIR/core/policies/falco-output.yaml" | kubectl apply -f -
# Update Helm z override (http_output)
helm upgrade --install falco falco/falco \
  --repo https://falcosecurity.github.io/charts \
  --version "$FALCO_VERSION" \
  --set driver.kind=modern_ebpf \
  --set http_output.enabled=true \
  --set http_output.url="$WEBHOOK_URL" \
  --set json_output=true \
  --namespace falco --create-namespace
# Restart Falco dla reload config
kubectl rollout restart daemonset/falco -n falco

echo "Instaluję Kyverno (policy enforcement)..."
helm upgrade --install kyverno kyverno/kyverno \
  --repo https://kyverno.github.io/kyverno/ \
  --version "$KYVERNO_VERSION" \
  --namespace kyverno --create-namespace

# Krok 4: Apply przykładowe policies (z core/policies)
echo "Aplicuję Kyverno policies..."
kubectl apply -f "$ROOT_DIR/core/policies/"

# DODANE: Krok 5: Build i deploy remediation webhook
echo "Buduję i deployuję remediation webhook..."
docker build -t autohealkube-webhook:latest "$ROOT_DIR/core/remediation-webhook/"
minikube image load autohealkube-webhook:latest
kubectl apply -f "$ROOT_DIR/core/manifests/webhook-deployment.yaml"

# Krok 6: Weryfikacja (dawny krok 5, rozszerzony)
echo "Weryfikuję instalacje..."
helm list
kubectl get pods -n falco
kubectl get pods -n kyverno
kubectl get pods -l app=remediation-webhook  # DODANE: Sprawdź webhook
kubectl logs -n falco -l app.kubernetes.io/name=falco  # DODANE: Logs Falco dla config check

echo "Setup lokalny ukończony! Teraz możesz testować: make scan, kubectl apply -f core/manifests/"