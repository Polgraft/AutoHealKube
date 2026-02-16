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

echo "Instaluję Kyverno (policy enforcement)..."
helm upgrade --install kyverno kyverno/kyverno \
  --repo https://kyverno.github.io/kyverno/ \
  --version "$KYVERNO_VERSION" \
  --namespace kyverno --create-namespace

# Krok 4: Apply przykładowe policies (z core/policies)
echo "Aplicuję Kyverno policies..."
kubectl apply -f "$ROOT_DIR/core/policies/"

# Krok 5: Weryfikacja
echo "Weryfikuję instalacje..."
helm list
kubectl get pods -n falco
kubectl get pods -n kyverno

echo "Setup lokalny ukończony! Teraz możesz testować: make scan, kubectl apply -f core/manifests/"