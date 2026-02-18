#!/bin/bash
# Skrypt do uruchomienia całej platformy lokalnie
# Wymaga: kubectl, helm, minikube/kind/k3d

set -e

echo "🚀 AutoHealKube - Uruchamianie platformy lokalnie"

# Sprawdzenie wymagań
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl nie jest zainstalowany"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ helm nie jest zainstalowany"; exit 1; }

# Sprawdzenie czy klaster Kubernetes jest dostępny
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Brak połączenia z klastrem Kubernetes"
    echo "💡 Uruchom najpierw minikube/kind/k3d"
    exit 1
fi

echo "✅ Klaster Kubernetes jest dostępny"

# Dodanie repozytoriów Helm
echo "📦 Dodawanie repozytoriów Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Budowanie obrazów Docker (opcjonalne, jeśli używamy lokalnego registry)
if command -v docker >/dev/null 2>&1; then
    echo "🐳 Budowanie obrazów Docker..."
    
    # Budowanie vulnerable-app
    docker build -t vulnerable-app:latest -f docker/vulnerable-app/Dockerfile docker/vulnerable-app/ || \
        docker build -t vulnerable-app:latest docker/vulnerable-app/
    
    # Budowanie auto-heal-webhook
    docker build -t auto-heal-webhook:latest python/
    
    # Ładowanie obrazów do minikube (jeśli używamy minikube)
    if command -v minikube >/dev/null 2>&1 && minikube status &> /dev/null; then
        echo "📥 Ładowanie obrazów do minikube..."
        minikube image load vulnerable-app:latest
        minikube image load auto-heal-webhook:latest
    fi
fi

# Instalacja zależności Helm
echo "📋 Instalacja zależności Helm..."
cd helm/platform
helm dependency update
cd ../..

# Instalacja platformy
echo "🔧 Instalacja platformy AutoHealKube..."
helm upgrade --install platform helm/platform/ \
    --namespace autohealkube \
    --create-namespace \
    --wait \
    --timeout 10m

# Instalacja polityk Kyverno
echo "🛡️ Instalacja polityk Kyverno..."
kubectl apply -f kyverno/policies/best-practices/
kubectl apply -f kyverno/policies/security/
kubectl apply -f kyverno/policies/test/

# Konfiguracja Falco (jeśli potrzebne)
echo "👁️ Konfiguracja Falco..."
kubectl create configmap falco-custom-rules \
    --from-file=falco/rules/custom-rules.yaml \
    --namespace autohealkube \
    --dry-run=client -o yaml | kubectl apply -f -

# Sprawdzenie statusu
echo "⏳ Oczekiwanie na gotowość zasobów..."
sleep 30

echo "📊 Status zasobów:"
kubectl get pods -n autohealkube
kubectl get svc -n autohealkube

echo ""
echo "✅ Platforma AutoHealKube została uruchomiona!"
echo ""
echo "🔗 Dostęp do usług:"
echo "   - Grafana: kubectl port-forward -n autohealkube svc/platform-grafana 3000:80"
echo "   - Prometheus: kubectl port-forward -n autohealkube svc/platform-prometheus-server 9090:80"
echo "   - Auto-heal webhook: kubectl port-forward -n autohealkube svc/auto-heal-webhook 8000:8000"
echo ""
echo "📝 Logi:"
echo "   - kubectl logs -n autohealkube -l app=auto-heal-webhook -f"
echo "   - kubectl logs -n autohealkube -l app=falco -f"
