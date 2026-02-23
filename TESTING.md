# Przewodnik testowania AutoHealKube

## Wymagania wstępne

### Opcja 1: Minikube (zalecane dla początkujących)
```bash
# Instalacja minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Uruchomienie
minikube start --driver=docker
minikube addons enable metrics-server
```

### Opcja 2: Kind (Kubernetes in Docker)
```bash
# Instalacja
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/

# Utworzenie klastra
kind create cluster --name autohealkube
```

### Opcja 3: k3d (lekkie)
```bash
# Instalacja
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Utworzenie klastra
k3d cluster create autohealkube
```

### Inne narzędzia
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Trivy (opcjonalnie, do testów lokalnych)
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
```

## Szybki start testowy

### 1. Uruchomienie całej platformy
```bash
# Metoda 1: Użyj skryptu
bash scripts/start-local.sh

# Metoda 2: Użyj Makefile
make start

# Metoda 3: Krok po kroku
make install          # Zainstaluj zależności Helm
make build-local       # Zbuduj obrazy Docker
make deploy-local      # Deployuj do Kubernetes
make apply-kyverno     # Zastosuj polityki Kyverno
make apply-falco       # Skonfiguruj Falco
```

### 2. Sprawdzenie statusu
```bash
# Status wszystkich zasobów
make status

# Lub ręcznie
kubectl get pods -n autohealkube
kubectl get svc -n autohealkube
kubectl get deployments -n autohealkube
```

### 3. Sprawdzenie logów
```bash
# Logi auto-heal webhook
make logs

# Logi Falco
make logs-falco

# Logi wszystkich komponentów
kubectl logs -n autohealkube -l app=auto-heal-webhook -f
kubectl logs -n autohealkube -l app=falco -f
kubectl logs -n autohealkube -l app=demo-app -f
```

## Testowanie poszczególnych komponentów

### Test 1: Testowanie Trivy (Security Scanning)

```bash
# Skanowanie obrazów Docker
make scan

# Skanowanie konfiguracji
make scan-config

# Skanowanie z custom policy
trivy fs --config trivy/trivy.yaml .

# Skanowanie konkretnego obrazu
trivy image vulnerable-app:latest
trivy image auto-heal-webhook:latest
```

**Oczekiwany wynik**: Trivy powinien wykryć podatności w `vulnerable-app` (to celowe!).

### Test 2: Testowanie Kyverno Policies

```bash
# Zastosuj polityki
make apply-kyverno

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

**Oczekiwany wynik**: Kyverno powinien zablokować utworzenie poda z `privileged: true`.

### Test 3: Testowanie Falco Rules

```bash
# Sprawdź czy Falco działa
kubectl get pods -n autohealkube -l app=falco

# Sprawdź logi Falco
kubectl logs -n autohealkube -l app=falco -f

# Test: Wykonaj podejrzaną akcję w podzie
kubectl exec -n autohealkube -it deployment/demo-app -- /bin/sh
# W podzie wykonaj:
# mount /host /mnt  # Próba ucieczki z kontenera
# exit
```

**Oczekiwany wynik**: Falco powinien wykryć podejrzaną akcję i wysłać alert do webhook.

### Test 4: Testowanie Auto-Heal Webhook

#### 4.1. Test ręczny webhook
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

**Oczekiwany wynik**: Webhook powinien zwrócić `{"status": "success", "action": {...}}` i usunąć pod.

#### 4.2. Test z rzeczywistym zdarzeniem Falco
```bash
# Sprawdź czy Falco wysyła do webhook
kubectl logs -n autohealkube -l app=auto-heal-webhook -f

# Wykonaj akcję która wywoła alert Falco
kubectl exec -n autohealkube deployment/demo-app -- sh -c "echo test > /etc/passwd"
```

**Oczekiwany wynik**: Falco wykryje modyfikację pliku systemowego, wyśle do webhook, webhook powinien zareagować.

### Test 5: Testowanie Vulnerable App

```bash
# Deploy vulnerable app (już powinna być wdrożona)
kubectl get pods -n autohealkube -l app=demo-app

# Port-forward
kubectl port-forward -n autohealkube svc/demo-app 8080:80

# Test różnych endpointów (wszystkie są celowo podatne!)
curl http://localhost:8080/
curl -X POST http://localhost:8080/exec -H "Content-Type: application/json" -d '{"command": "whoami"}'
curl -X POST http://localhost:8080/eval -H "Content-Type: application/json" -d '{"code": "1+1"}'
curl http://localhost:8080/env
```

**Ostrzeżenie**: Te endpointy są celowo podatne! Używaj tylko w środowisku testowym.

### Test 6: Testowanie Prometheus Alerts

```bash
# Port-forward do Prometheus
kubectl port-forward -n autohealkube svc/platform-prometheus-server 9090:80

# Otwórz http://localhost:9090 w przeglądarce
# Sprawdź alerty w Prometheus UI

# Test: Wyślij alert do webhook (symulacja)
curl -X POST http://localhost:8000/webhook/prometheus \
  -H "Content-Type: application/json" \
  -d '{
    "status": "firing",
    "labels": {
      "alertname": "PodCrashLooping",
      "severity": "critical",
      "pod": "demo-app-xxx",
      "namespace": "autohealkube"
    },
    "annotations": {
      "description": "Pod is crash looping"
    },
    "startsAt": "2024-01-01T00:00:00Z"
  }'
```

**Oczekiwany wynik**: Webhook powinien zrestartować deployment.

## Testowanie monitoringu

### Grafana
```bash
kubectl port-forward -n autohealkube svc/platform-grafana 3000:80
# Otwórz http://localhost:3000
# Login: admin / admin (zmień hasło przy pierwszym logowaniu)
```

### Prometheus
```bash
kubectl port-forward -n autohealkube svc/platform-prometheus-server 9090:80
# Otwórz http://localhost:9090
```

### Loki (jeśli włączony)
```bash
kubectl port-forward -n autohealkube svc/platform-loki 3100:80
# Otwórz http://localhost:3100
```

## Debugowanie

### Sprawdzenie czy wszystkie komponenty działają
```bash
# Status wszystkich podów
kubectl get pods -n autohealkube

# Jeśli jakiś pod nie działa:
kubectl describe pod <pod-name> -n autohealkube
kubectl logs <pod-name> -n autohealkube

# Sprawdzenie eventów
kubectl get events -n autohealkube --sort-by='.lastTimestamp'
```

### Sprawdzenie konfiguracji Falco
```bash
# Sprawdź czy custom rules są załadowane
kubectl exec -n autohealkube -l app=falco -- cat /etc/falco/custom-rules.yaml
```

### Sprawdzenie polityk Kyverno
```bash
# Lista polityk
kubectl get clusterpolicies

# Szczegóły polityki
kubectl describe clusterpolicy require-non-root

# Test polityki
kyverno test kyverno/policies/security/require-non-root.yaml
```

## 🧹 Czyszczenie po testach

```bash
# Usuń wszystkie zasoby
make clean

# Lub ręcznie
helm uninstall platform --namespace autohealkube
kubectl delete namespace autohealkube

# Usuń obrazy Docker
make clean-all
```

## Checklist testowy

- [ ] Wszystkie pody są w stanie Running
- [ ] Trivy wykrywa podatności w vulnerable-app
- [ ] Kyverno blokuje niebezpieczne zasoby
- [ ] Falco wykrywa podejrzane akcje
- [ ] Webhook odbiera zdarzenia z Falco
- [ ] Webhook wykonuje akcje naprawcze (delete/restart)
- [ ] Prometheus zbiera metryki
- [ ] Grafana wyświetla dashboards
- [ ] Auto-heal działa automatycznie

## Znane problemy

1. **Falco nie startuje**: Może wymagać kernel headers. W minikube: `minikube ssh -- sudo apt-get install linux-headers-$(uname -r)`

2. **Kyverno nie działa**: Sprawdź czy Kyverno jest zainstalowany: `kubectl get pods -n kyverno`

3. **Webhook nie otrzymuje zdarzeń**: Sprawdź konfigurację Falco w `falco/rules/falco.yaml` - URL webhook musi być poprawny

4. **Obrazy nie są dostępne**: W minikube użyj `minikube image load` lub skonfiguruj lokalne registry

## Wskazówki

- Użyj `kubectl get events -n autohealkube -w` do śledzenia eventów w czasie rzeczywistym
- Użyj `kubectl logs -f` do śledzenia logów w czasie rzeczywistym
- Sprawdź dokumentację każdego komponentu dla zaawansowanych testów
