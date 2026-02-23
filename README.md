# AutoHealKube

Platforma DevSecOps dla Kubernetes z automatycznym naprawianiem problemów bezpieczeństwa i wydajnościowych.

## 📖 Dokumentacja

- **[README.md](README.md)** - Główna dokumentacja projektu
- **[TESTING.md](TESTING.md)** - Szczegółowy przewodnik testowania
- **[GITHUB_SETUP.md](GITHUB_SETUP.md)** - Instrukcje wypchnięcia do GitHub

## 🎯 Funkcjonalności

- **🔍 Security Scanning**: Trivy do skanowania obrazów i kodu
- **👁️ Runtime Security**: Falco do monitorowania runtime
- **🛡️ Policy Enforcement**: Kyverno do egzekwowania polityk bezpieczeństwa
- **📊 Monitoring**: Prometheus + Grafana do monitorowania
- **📝 Logging**: Loki do agregacji logów
- **🔧 Auto-Healing**: Automatyczne naprawianie problemów przez webhook

## 📁 Struktura projektu

```
AutoHealKube/
├── docker/                    # Obrazy Docker
│   ├── Dockerfile            # Bezpieczny obraz przykładowy
│   └── vulnerable-app/       # Podatna aplikacja do testów
├── helm/platform/            # Umbrella Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/            # Szablony Kubernetes
├── trivy/                    # Konfiguracja Trivy
│   ├── trivy.yaml
│   └── .trivyignore
├── falco/                    # Reguły Falco
│   └── rules/
│       ├── custom-rules.yaml
│       └── falco.yaml
├── kyverno/                  # Polityki Kyverno
│   └── policies/
│       ├── best-practices/
│       ├── security/
│       └── test/
├── python/                   # Auto-heal webhook
│   ├── auto_heal_webhook.py
│   ├── remediation.py
│   └── requirements.txt
├── .github/workflows/        # CI/CD pipeline
├── scripts/                  # Skrypty pomocnicze
└── Makefile                  # Automatyzacja
```

## 🚀 Szybki start

### Wypchnięcie do GitHub

```bash
# Metoda 1: Użyj skryptu (interaktywny)
bash scripts/push-to-github.sh

# Metoda 2: Ręcznie
git add .
git commit -m "feat: Dodanie kompletnej struktury AutoHealKube"
git push origin main
```

Szczegółowe instrukcje w [GITHUB_SETUP.md](GITHUB_SETUP.md).

### Wymagania do testowania

- Kubernetes cluster (minikube/kind/k3d)
- kubectl
- helm 3.x
- docker (opcjonalnie)

### Instalacja lokalna

```bash
# Uruchomienie całej platformy jednym poleceniem
make start

# Lub użyj skryptu
bash scripts/start-local.sh
```

### Instalacja ręczna

```bash
# 1. Zainstaluj zależności Helm
make install

# 2. Zbuduj obrazy Docker
make build-local

# 3. Deployuj platformę
make deploy-local

# 4. Zastosuj polityki Kyverno
make apply-kyverno

# 5. Skonfiguruj Falco
make apply-falco
```

## 📋 Dostępne komendy Make

```bash
make help          # Wyświetla pomoc
make build         # Buduje obrazy Docker
make scan          # Skanuje podatności (Trivy)
make lint          # Lintuje Helm charts
make test          # Uruchamia testy
make deploy        # Deployuje platformę
make status        # Sprawdza status zasobów
make logs          # Wyświetla logi webhook
make clean         # Usuwa zasoby
```

## 🔧 Konfiguracja

### Helm Values

Edytuj `helm/platform/values.yaml` aby dostosować konfigurację:

- Włączanie/wyłączanie komponentów
- Limity zasobów
- Konfiguracja persistence
- Ustawienia bezpieczeństwa

### Falco Rules

Dodaj własne reguły w `falco/rules/custom-rules.yaml`:

```yaml
- rule: My Custom Rule
  desc: Opis reguły
  condition: ...
  output: ...
  priority: WARNING
```

### Kyverno Policies

Dodaj polityki w odpowiednich katalogach:
- `kyverno/policies/security/` - Polityki bezpieczeństwa
- `kyverno/policies/best-practices/` - Best practices
- `kyverno/policies/test/` - Polityki testowe

## 🔐 Auto-Healing

Webhook automatycznie reaguje na:

### Falco Events
- **Container Escape Attempt** → Usuwa pod
- **Privilege Escalation** → Usuwa pod
- **Unauthorized Process Execution** → Restartuje pod

### Prometheus Alerts
- **PodCrashLooping** → Restartuje deployment
- **HighMemoryUsage** → Zmniejsza repliki
- **HighCPUUsage** → Zmniejsza repliki

### Konfiguracja akcji

Edytuj `python/remediation.py` aby dostosować mapowanie reguł na akcje.

## 📊 Monitoring

### Dostęp do usług

```bash
# Grafana
kubectl port-forward -n autohealkube svc/platform-grafana 3000:80
# Otwórz http://localhost:3000 (admin/admin)

# Prometheus
kubectl port-forward -n autohealkube svc/platform-prometheus-server 9090:80
# Otwórz http://localhost:9090

# Auto-heal webhook
kubectl port-forward -n autohealkube svc/auto-heal-webhook 8000:8000
# Otwórz http://localhost:8000/docs

### Loki (logi)
Loki jest deployowany w namespace `autohealkube` i dostępny pod adresem `http://platform-loki:3100`.

#### Dodanie Loki jako data source w Grafanie

```bash
# 1. Otwórz Grafanę
kubectl port-forward -n autohealkube svc/platform-grafana 3000:80

```

## 🔍 Security Scanning

### Trivy

```bash
# Skanowanie obrazów
make scan

# Skanowanie konfiguracji
make scan-config

# Skanowanie z custom policy
trivy fs --config trivy/trivy.yaml .
```

## 🧪 Testowanie

Szczegółowy przewodnik testowania znajduje się w [TESTING.md](TESTING.md).

### Szybki test

```bash
# Uruchomienie całej platformy
make start

# Sprawdzenie statusu
make status

# Testowanie polityk Kyverno
make test

# Skanowanie bezpieczeństwa
make scan
```

Zobacz [TESTING.md](TESTING.md) dla pełnych instrukcji testowania wszystkich komponentów.

## 🚢 CI/CD

Pipeline GitHub Actions automatycznie:

1. Skanuje kod i obrazy (Trivy)
2. Buduje i pushuje obrazy Docker
3. Lintuje Helm charts
4. Testuje polityki Kyverno
5. Deployuje do staging/production

Zobacz `.github/workflows/devsecops-pipeline.yml` dla szczegółów.

## 📝 Polityki bezpieczeństwa

Platforma wdraża następujące polityki:

### Kyverno
- ✅ Wymagane limity zasobów
- ✅ Wymagane etykiety
- ✅ Brak kontenerów privileged
- ✅ Wymagany non-root user
- ✅ Brak hostPath volumes

### Falco
- ✅ Wykrywanie ucieczki z kontenera
- ✅ Wykrywanie eskalacji uprawnień
- ✅ Wykrywanie podejrzanej aktywności sieciowej
- ✅ Wykrywanie modyfikacji plików systemowych

## 🤝 Wsparcie

W razie problemów:
1. Sprawdź logi: `make logs`
2. Sprawdź status: `make status`
3. Sprawdź dokumentację komponentów

## 📄 Licencja

MIT

- [Falco](https://falco.org/)
- [Kyverno](https://kyverno.io/)
- [Trivy](https://aquasecurity.github.io/trivy/)
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)
