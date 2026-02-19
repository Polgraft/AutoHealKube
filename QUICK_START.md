# 🚀 Szybki start - Uruchomienie i testowanie AutoHealKube

## Krok 1: Uruchomienie lokalnego klastra Kubernetes

### Opcja A: Minikube (zalecane)
```bash
# Uruchom minikube
minikube start --driver=docker

# Włącz metrics-server (potrzebny dla niektórych komponentów)
minikube addons enable metrics-server

# Sprawdź status
kubectl cluster-info
```

### Opcja B: k3d (szybsze, lżejsze)
```bash
# Utwórz klaster
k3d cluster create autohealkube

# Sprawdź status
kubectl cluster-info
```

## Krok 2: Uruchomienie całej platformy

### Metoda 1: Automatyczny skrypt (najłatwiejsze)
```bash
cd /home/kolpitk/AutoHealKube
bash scripts/start-local.sh
```

### Metoda 2: Makefile
```bash
cd /home/kolpitk/AutoHealKube
make start
```

### Metoda 3: Krok po kroku
```bash
# 1. Dodaj repozytoria Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# 2. Zbuduj obrazy Docker
make build-local

# 3. Jeśli używasz minikube, załaduj obrazy
minikube image load vulnerable-app:latest
minikube image load auto-heal-webhook:latest

# 4. Zainstaluj zależności Helm
make install

# 5. Deployuj platformę
make deploy-local

# 6. Zastosuj polityki Kyverno
make apply-kyverno

# 7. Skonfiguruj Falco
make apply-falco
```

## Krok 3: Sprawdzenie statusu

```bash
# Status wszystkich zasobów
make status

# Lub ręcznie
kubectl get pods -n autohealkube
kubectl get svc -n autohealkube
kubectl get deployments -n autohealkube

# Sprawdź czy wszystkie pody są gotowe (powinny być Running)
kubectl get pods -n autohealkube -w
```

## Krok 4: Testowanie komponentów

### Test 1: Auto-Heal Webhook
```bash
# Port-forward do webhook
kubectl port-forward -n autohealkube svc/auto-heal-webhook 8000:8000

# W innym terminalu - test health check
curl http://localhost:8000/health

# Test webhook z przykładowym zdarzeniem Falco
curl -X POST http://localhost:8000/webhook/falco \
  -H "Content-Type: application/json" \
  -d '{
    "output": "Container escape attempt detected",
    "priority": "CRITICAL",
    "rule": "Container Escape Attempt",
    "time": "2024-01-01T00:00:00Z",
    "output_fields": {
      "k8s.ns.name": "autohealkube",
      "k8s.pod.name": "demo-app-xxx",
      "k8s.container.name": "vulnerable-app"
    },
    "hostname": "test-host"
  }'
```

### Test 2: Vulnerable App
```bash
# Port-forward
kubectl port-forward -n autohealkube svc/demo-app 8080:80

# Test endpointów (wszystkie są celowo podatne!)
curl http://localhost:8080/
curl -X POST http://localhost:8080/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "whoami"}'
```

### Test 3: Grafana Dashboard
```bash
# Port-forward
kubectl port-forward -n autohealkube svc/platform-grafana 3000:80

# Otwórz w przeglądarce: http://localhost:3000
# Login: admin / admin (zmień hasło przy pierwszym logowaniu)
```

### Test 4: Prometheus
```bash
# Port-forward
kubectl port-forward -n autohealkube svc/platform-prometheus-server 9090:80

# Otwórz w przeglądarce: http://localhost:9090
```

### Test 5: Logi komponentów
```bash
# Logi auto-heal webhook
make logs

# Logi Falco
make logs-falco

# Logi demo-app
kubectl logs -n autohealkube -l app=demo-app -f
```

## Krok 5: Testowanie Security Scanning (Trivy)

```bash
# Skanowanie obrazów Docker
make scan

# Skanowanie konfiguracji
make scan-config

# Skanowanie z custom policy
trivy fs --config trivy/trivy.yaml .
```

## Krok 6: Testowanie Kyverno Policies

```bash
# Sprawdź status polityk
kubectl get clusterpolicies

# Test: Spróbuj utworzyć pod z privileged (powinno się nie udać)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: autohealkube
spec:
  containers:
  - name: test
    image: nginx
    securityContext:
      privileged: true
EOF

# Powinno zwrócić błąd - polityka blokuje privileged containers
```

## Krok 7: Testowanie Falco

```bash
# Sprawdź logi Falco
kubectl logs -n autohealkube -l app=falco -f

# Wykonaj podejrzaną akcję w podzie
kubectl exec -n autohealkube -it deployment/demo-app -- /bin/sh
# W podzie wykonaj:
# mount /host /mnt  # Próba ucieczki z kontenera
# exit
```

## Krok 8: Testowanie Auto-Healing

### Symulacja zdarzenia Falco
```bash
# Port-forward do webhook (jeśli nie masz już)
kubectl port-forward -n autohealkube svc/auto-heal-webhook 8000:8000

# Wyślij zdarzenie CRITICAL (powinno usunąć pod)
curl -X POST http://localhost:8000/webhook/falco \
  -H "Content-Type: application/json" \
  -d '{
    "output": "Container escape attempt detected",
    "priority": "CRITICAL",
    "rule": "Container Escape Attempt",
    "time": "2024-01-01T00:00:00Z",
    "output_fields": {
      "k8s.ns.name": "autohealkube",
      "k8s.pod.name": "demo-app-xxx",
      "k8s.container.name": "vulnerable-app",
      "k8s.deployment.name": "demo-app"
    },
    "hostname": "test-host"
  }'

# Sprawdź czy pod został usunięty
kubectl get pods -n autohealkube -l app=demo-app
```

## Krok 9: Testowanie CI/CD Pipeline

### Lokalnie (bez GitHub Actions)
```bash
# Lint Helm charts
make lint

# Test polityk Kyverno
make test

# Security scan
make scan
```

### Na GitHub
1. Wypchnij zmiany:
```bash
git add .
git commit -m "test: testowanie platformy"
git push origin main
```

2. Sprawdź GitHub Actions:
   - Przejdź do: https://github.com/Polgraft/AutoHealKube/actions
   - Sprawdź czy wszystkie joby przechodzą

## Krok 10: Czyszczenie

```bash
# Usuń wszystkie zasoby
make clean

# Lub ręcznie
helm uninstall platform --namespace autohealkube
kubectl delete namespace autohealkube

# Zatrzymaj minikube
minikube stop

# Lub usuń klaster k3d
k3d cluster delete autohealkube
```

## 🐛 Troubleshooting

### Problem: Pody nie startują
```bash
# Sprawdź szczegóły poda
kubectl describe pod <pod-name> -n autohealkube

# Sprawdź logi
kubectl logs <pod-name> -n autohealkube

# Sprawdź eventy
kubectl get events -n autohealkube --sort-by='.lastTimestamp'
```

### Problem: Obrazy nie są dostępne
```bash
# W minikube załaduj obrazy
minikube image load vulnerable-app:latest
minikube image load auto-heal-webhook:latest

# Sprawdź czy obrazy są dostępne
minikube image ls
```

### Problem: Falco nie startuje
```bash
# W minikube może wymagać kernel headers
minikube ssh -- sudo apt-get update
minikube ssh -- sudo apt-get install linux-headers-$(uname -r)
```

### Problem: Kyverno nie działa
```bash
# Sprawdź czy Kyverno jest zainstalowany
kubectl get pods -n kyverno

# Jeśli nie, zainstaluj ręcznie
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
```

## 📊 Checklist testowy

- [ ] Klaster Kubernetes działa
- [ ] Wszystkie pody są w stanie Running
- [ ] Auto-heal webhook odpowiada na /health
- [ ] Vulnerable app odpowiada
- [ ] Grafana jest dostępna
- [ ] Prometheus jest dostępny
- [ ] Trivy wykrywa podatności w vulnerable-app
- [ ] Kyverno blokuje niebezpieczne zasoby
- [ ] Falco wykrywa podejrzane akcje
- [ ] Webhook wykonuje akcje naprawcze

## 💡 Przydatne komendy

```bash
# Podgląd logów w czasie rzeczywistym
kubectl logs -n autohealkube -l app=auto-heal-webhook -f

# Podgląd eventów
kubectl get events -n autohealkube -w

# Shell do poda
kubectl exec -n autohealkube -it deployment/demo-app -- /bin/sh

# Sprawdzenie konfiguracji
kubectl get configmap -n autohealkube
kubectl get secrets -n autohealkube
```

## 📚 Więcej informacji

- Szczegółowy przewodnik: [TESTING.md](TESTING.md)
- Dokumentacja projektu: [README.md](README.md)
