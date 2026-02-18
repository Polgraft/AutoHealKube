# AutoHealKube

Autonomiczna platforma DevSecOps do wykrywania i auto-naprawy zagrożeń w kontenerach Kubernetes w czasie rzeczywistym.

## Opis projektu
- **Cel**: Skanowanie obrazów i manifestów (shift-left security), wykrywanie zagrożeń runtime, wymuszanie polityk, automatyczna remediacja (np. patch podów) oraz wizualizacja incydentów.
- **Innowacja**: Custom webhook w Python (FastAPI) odbiera alerty z Falco, analizuje je i automatycznie patchuje zasoby Kubernetes (np. dodaje securityContext non-root, rollout restart).
- **Zakres**: Lokalnie (Minikube) do chmury (GCP GKE). Reusable template – możesz skopiować i dostosować do skanowania własnych obrazów/manifestów.
- **Technologie**: Ansible, Prometheus, Docker, Python, ArgoCD, Terraform, Kubernetes, Helm, GitHub Actions, Kyverno, GCP, Git, Trivy, Grafana Loki, Falco.
- **Data**: Projekt oparty na wersjach z lutego 2026 (Kubernetes 1.29+, Falco 0.37+, etc.).

## Quick Start
1. Sklonuj repo: `git clone https://github.com/TWOJ_USERNAME/AutoHealKube.git` (użyj jako template – włącz w GitHub settings).
2. Ustaw zmienne: Edytuj `values.yaml` (np. URL webhook, thresholds dla alertów). Ustaw secrets w GitHub (np. GCP creds).
3. Ustaw swój obraz do skanowania: Zmodyfikuj `core/manifests/safe-deployment.yaml` lub dodaj własny (ustaw env `IMAGE_NAME`).
4. Uruchom setup: `make setup` (instaluje deps via Ansible).
5. Skanuj i deployuj: `make scan` (Trivy check), `make deploy-cloud` (Terraform + ArgoCD sync).
6. Testuj: Deployuj przykłady z `tests/e2e/vulnerable-examples/` (tylko do testów – ostrzeżenie poniżej).

## Struktura repo
- `.github/workflows/`: CI/CD pipelines (build, Trivy scan, Argo sync).
- `ansible/`: Playbooks do automatyzacji setupu.
- `bootstrap/`: Skrypty startowe (np. call Ansible).
- `core/`: Reusable, bezpieczny kod (webhook, polityki Kyverno, dashboard HTMX, manifesty safe, monitoring Prometheus).
- `tests/e2e/vulnerable-examples/`: Przykłady vuln (do demo/testów tylko – nie używaj w prod!).
- `infra/`: Terraform IaC dla GCP (VPC, GKE).
- `Makefile`: Komendy ułatwienia (setup, scan, deploy).
- `values.yaml`: Konfiguracja (URL, thresholds).
- `README.md`: Ten plik.

## Ostrzeżenie dla vulnerable-examples/
Folder `tests/e2e/vulnerable-examples/` zawiera vulnerable przykłady (np. vuln-nginx Dockerfile, vuln-test.yaml) tylko do demo i testów. **Nie deployuj ich w produkcji!** Używaj do symulacji ataków (np. runtime threats w Falco).

## Demo Vulns (vulnerable-examples)
- `vuln-nginx/Dockerfile`: Przykładowy obraz z known vuln (do Trivy scan block).
- `vuln-test.yaml`: Manifest bez securityContext (Kyverno mutate/fix).

## Następne kroki
- Uruchom lokalnie: `bootstrap/install-local.sh`.
- Monitoring: Dashboard w Grafana/Loki pokazuje ostatnie incydenty.
- Pełna dokumentacja w trakcie budowy.

Licencja: MIT. Kontributuj via PR!

## Użycie safe-deployment
- Edytuj `core/manifests/safe-deployment.yaml`: Zmień image na swój (np. myapp:v1).
- Skanuj: `make scan` – pass jeśli no HIGH vulns.
- Deploy: `kubectl apply -f core/manifests/safe-deployment.yaml` – ArgoCD auto-sync.