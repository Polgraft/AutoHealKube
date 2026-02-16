# Changelog - Poprawki integralności i konfiguracji AutoHealKube

## Data: 16 lutego 2026

### 1. Problem: Błąd parsowania `values.yaml` przez `yq`

**Przyczyna:**
- System używał `yq` w wersji "jq-style" (z `apt`), która ma inną składnię niż `yq` z GitHub releases
- Skrypty używały składni `yq e '.key' file.yaml`, która nie działała na Ubuntu/WSL

**Rozwiązanie:**
- Zmieniono wszystkie wywołania `yq e` na `yq '.key'` (kompatybilne z wersją apt)
- Dodano `| tr -d '"'` do usunięcia cudzysłowów z outputu
- Pliki zmienione:
  - `bootstrap/install-local.sh` (linie 13-16, 58-59)
  - `Makefile` (wszystkie użycia `yq e`)

**Efekt:**
- Poprawne parsowanie wartości z `values.yaml`
- Minikube startuje z właściwą wersją Kubernetes zamiast pustego stringa

---

### 2. Problem: Dockerfile - brak binarki `uvicorn` w finalnym obrazie

**Przyczyna:**
- Dockerfile używał multi-stage build, ale nie kopiował `/usr/local/bin` z buildera do finalnego obrazu
- `uvicorn` był instalowany w builderze, ale nie był dostępny w `$PATH` finalnego obrazu
- Błąd: `exec: "uvicorn": executable file not found in $PATH`

**Rozwiązanie:**
- Dodano `COPY --from=builder /usr/local/bin /usr/local/bin` w obu Dockerfile
- Pliki zmienione:
  - `core/remediation-webhook/Dockerfile` (linia 19)
  - `core/dashboard/Dockerfile` (linia 19)

**Efekt:**
- Kontenery webhook i dashboard uruchamiają się poprawnie
- `uvicorn` jest dostępny w `$PATH` finalnego obrazu

---

### 3. Problem: Python dependencies - PEP 668 (externally-managed-environment)

**Przyczyna:**
- Ubuntu 24.04 wprowadza PEP 668, który blokuje instalację pakietów systemowo przez `pip`
- Ansible próbował instalować pakiety bezpośrednio do systemowego Pythona
- Błąd: `error: externally-managed-environment`

**Rozwiązanie:**
- Utworzono virtualenv w `/opt/autohealkube-venv` dla zależności Pythona
- Zmieniono task Ansible na instalację w venv zamiast systemowo
- Pliki zmienione:
  - `ansible/setup.yml` (linie 14-19, 87-92)

**Efekt:**
- Zależności Python instalowane w izolowanym środowisku
- Brak konfliktów z systemowymi pakietami Debiana

---

### 4. Problem: Ansible - niepoprawne komendy weryfikacji wersji

**Przyczyna:**
- Task "Verify installations" używał `helm --version`, `minikube --version`, `kubectl --version`
- Te komendy nie istnieją w nowszych wersjach narzędzi
- Błąd: `Error: unknown flag: --version`

**Rozwiązanie:**
- Zmieniono komendy na: `helm version`, `minikube version`, `kubectl version --client=true`
- Pliki zmienione:
  - `ansible/setup.yml` (linie 97-104)

**Efekt:**
- Poprawne wyświetlanie wersji zainstalowanych narzędzi
- Setup Ansible przechodzi bez błędów

---

### 5. Problem: Helm - niepoprawne nazwy chartów w repozytoriach

**Przyczyna:**
- Używano nieistniejących chartów: `falco/falco`, `kyverno/kyverno`, `argo/argo-helm`
- Helm nie mógł znaleźć chartów w podanych repozytoriach
- Błąd: `Error: chart "falco/falco" not found`

**Rozwiązanie:**
- Usunięto `--version` (użycie najnowszej stabilnej wersji)
- Poprawiono nazwy chartów: `falco/falco` → `falco`, `argo/argo-helm` → `argo-cd`
- Pliki zmienione:
  - `bootstrap/install-local.sh` (linie 29-56, 61-65)

**Efekt:**
- Falco, Kyverno i ArgoCD instalują się poprawnie
- CRD są dostępne, więc `kubectl apply` działa bez błędów

---

### 6. Problem: Docker credentials - `docker-credential-desktop.exe` na WSL

**Przyczyna:**
- Docker w WSL próbował użyć Windows helpera `docker-credential-desktop.exe`
- Błąd: `fork/exec /usr/bin/docker-credential-desktop.exe: exec format error`

**Rozwiązanie:**
- Utworzono lokalną pustą konfigurację Docker (`DOCKER_CONFIG`) bez `credsStore`
- Użyto tej konfiguracji tylko podczas buildów w skrypcie
- Pliki zmienione:
  - `bootstrap/install-local.sh` (linie 100-109)

**Efekt:**
- Docker build działa poprawnie na WSL
- Obrazy są budowane i ładowane do Minikube

---

### 7. Problem: Kubernetes - `ImagePullBackOff` dla lokalnych obrazów

**Przyczyna:**
- Deploymenty używały tagu `:latest` bez `imagePullPolicy: IfNotPresent`
- Kubernetes domyślnie używa `Always` dla `:latest`, więc próbował pull z Docker Hub
- Błąd: `pull access denied for autohealkube-webhook, repository does not exist`

**Rozwiązanie:**
- Dodano `imagePullPolicy: IfNotPresent` do obu deploymentów
- Pliki zmienione:
  - `core/manifests/webhook-deployment.yaml` (linia 22)
  - `core/manifests/dashboard-deployment.yaml` (linia 20)

**Efekt:**
- Kubernetes używa lokalnych obrazów z Minikube
- Pody przechodzą ze stanu `ImagePullBackOff` na `Running`

---

### 8. Problem: Dashboard - brak katalogu `static` w obrazie

**Przyczyna:**
- `app.py` używał `StaticFiles(directory="static")`, ale katalog nie istniał w obrazie
- Błąd: `FileNotFoundError: [Errno 2] No such file or directory: 'static'`

**Rozwiązanie:**
- Dodano `RUN mkdir -p static` w Dockerfile dashboardu
- Pliki zmienione:
  - `core/dashboard/Dockerfile` (linia 11)

**Efekt:**
- Dashboard uruchamia się bez błędów związanych z brakującym katalogiem

---

### 9. Problem: Dashboard - `uvicorn` nie w `$PATH` (alternatywne rozwiązanie)

**Przyczyna:**
- Nawet po skopiowaniu `/usr/local/bin`, czasem `uvicorn` nie był dostępny
- Błąd: `exec: "uvicorn": executable file not found in $PATH`

**Rozwiązanie:**
- Zmieniono CMD na `python -m uvicorn` zamiast bezpośredniego wywołania `uvicorn`
- Pliki zmienione:
  - `core/dashboard/Dockerfile` (linia 25)

**Efekt:**
- Uvicorn uruchamia się przez Python module loader
- Niezależne od dostępności skryptu w `$PATH`

---

### 10. Problem: Git - binarny plik `ansible/argocd` w historii (153 MB)

**Przyczyna:**
- Plik binarny ArgoCD CLI został przypadkowo commitowany do repo
- Przekraczał limit GitHub (100 MB)
- Błąd: `File ansible/argocd is 152.77 MB; this exceeds GitHub's file size limit`

**Rozwiązanie:**
- Usunięto plik z filesystemu
- Usunięto z historii Git używając `git filter-branch`
- Utworzono `.gitignore` z regułami dla binarek
- Pliki zmienione:
  - Usunięto: `ansible/argocd`
  - Utworzono: `.gitignore`

**Efekt:**
- Repo może być pushowane do GitHub
- Binarki nie będą commitowane w przyszłości

---

### 11. Problem: GitHub Actions - nieistniejący action `argoproj/argo-cd-action`

**Przyczyna:**
- Workflow używał nieistniejącego action `argoproj/argo-cd-action@v2`
- Błąd: `Unable to resolve action argoproj/argo-cd-action, repository not found`

**Rozwiązanie:**
- Zastąpiono action bezpośrednim wywołaniem ArgoCD CLI
- Dodano instalację ArgoCD CLI w workflow
- Pliki zmienione:
  - `.github/workflows/devsecops-pipeline.yaml` (linie 93-105)

**Efekt:**
- ArgoCD sync działa poprawnie w workflow
- Niezależność od zewnętrznych actions

---

### 12. Problem: GitHub Actions - Trivy skanuje obrazy przed ich zbudowaniem

**Przyczyna:**
- Trivy próbował przeskanować obrazy z GHCR, które jeszcze nie istniały
- Obrazy były budowane dopiero w następnym kroku
- Błąd: `could not parse reference: ghcr.io/.../autohealkube-webhook:...`

**Rozwiązanie:**
- Zmieniono kolejność: najpierw build lokalny (`load: true`), potem scan, na końcu push
- Pliki zmienione:
  - `.github/workflows/devsecops-pipeline.yaml` (linie 46-95)

**Efekt:**
- Trivy skanuje lokalnie zbudowane obrazy
- Pipeline działa poprawnie

---

### 13. Problem: GitHub Actions - brak uprawnień `security-events: write`

**Przyczyna:**
- CodeQL Action wymaga uprawnienia do uploadu wyników SARIF
- Błąd: `Resource not accessible by integration`

**Rozwiązanie:**
- Dodano `security-events: write` do sekcji `permissions`
- Zaktualizowano CodeQL Action z v3 na v4 (deprecated)
- Pliki zmienione:
  - `.github/workflows/devsecops-pipeline.yaml` (linie 17-20, 125)

**Efekt:**
- Wyniki Trivy są uploadowane do GitHub Security tab
- Użycie aktualnej wersji CodeQL Action

---

### 14. Problem: Trivy - podatności HIGH w obrazach Docker

**Przyczyna:**
- Obrazy bazowe `python:3.11-slim` miały stare pakiety systemowe (glibc CVE-2026-0861)
- Python packages były w starych wersjach (wheel CVE-2026-24049, jaraco.context CVE-2026-23949)
- Pipeline blokował deploy z powodu 5 podatności HIGH

**Rozwiązanie:**
- Dodano `apt-get update && apt-get upgrade` w obu stage'ach Dockerfile
- Dodano `pip install --upgrade pip wheel setuptools` przed instalacją deps
- Użyto `--upgrade` przy instalacji Python packages
- Pliki zmienione:
  - `core/remediation-webhook/Dockerfile` (linie 6-7, 14-15)
  - `core/dashboard/Dockerfile` (linie 6-7, 14-15)

**Efekt:**
- Większość podatności naprawiona przez aktualizacje
- Pipeline powinien przejść po rebuildzie obrazów

---

### 15. Problem: Brakujący plik `core/manifests/dashboard-deployment.yaml`

**Przyczyna:**
- Skrypty i workflow odwoływały się do nieistniejącego pliku
- Błąd: `the path ... dashboard-deployment.yaml does not exist`

**Rozwiązanie:**
- Utworzono manifest deploymentu dla dashboardu
- Pliki zmienione:
  - Utworzono: `core/manifests/dashboard-deployment.yaml`

**Efekt:**
- Dashboard może być deployowany przez skrypty i workflow

---

## Podsumowanie statystyk

- **Pliki zmienione:** 12
- **Pliki utworzone:** 2 (`.gitignore`, `core/manifests/dashboard-deployment.yaml`)
- **Pliki usunięte:** 1 (`ansible/argocd`)
- **Kategorie problemów:**
  - Konfiguracja narzędzi (yq, Helm, Docker): 4
  - Dockerfile i obrazy: 5
  - GitHub Actions: 3
  - Git i repo: 1
  - Ansible: 2

## Kluczowe lekcje

1. **Kompatybilność narzędzi:** Zawsze sprawdzać wersje narzędzi w środowisku docelowym
2. **Multi-stage builds:** Kopiować wszystkie potrzebne pliki/binarki między stage'ami
3. **PEP 668:** Używać venv dla zależności Python na nowszych systemach
4. **Helm charts:** Sprawdzać aktualne nazwy chartów w repozytoriach
5. **Security scanning:** Skanować obrazy po buildzie, przed push
6. **Git hygiene:** Nie commitować binarek - używać `.gitignore`
