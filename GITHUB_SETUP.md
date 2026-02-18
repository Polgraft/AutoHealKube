# 🚀 Wypchnięcie projektu do GitHub

## Krok 1: Przygotowanie zmian

### Sprawdzenie statusu
```bash
cd /home/kolpitk/AutoHealKube
git status
```

### Dodanie nowych plików
```bash
# Dodaj wszystkie nowe pliki
git add .

# Lub selektywnie:
git add docker/
git add helm/
git add falco/
git add kyverno/
git add python/
git add trivy/
git add scripts/
git add .github/
git add Makefile
git add README.md
git add TESTING.md
git add .gitignore
```

### Usunięcie starych plików (jeśli są w git)
```bash
# Sprawdź co zostało usunięte
git status

# Jeśli chcesz usunąć stare pliki z repozytorium:
git add -u  # Dodaje zmiany w śledzonych plikach (w tym usunięcia)
```

## Krok 2: Commit zmian

```bash
# Commit z opisowym komunikatem
git commit -m "feat: Dodanie kompletnej struktury AutoHealKube

- Dodano Helm umbrella chart z Prometheus, Grafana, Loki, Falco, Kyverno
- Dodano auto-heal webhook w Python (FastAPI)
- Dodano custom reguły Falco
- Dodano polityki bezpieczeństwa Kyverno
- Dodano konfigurację Trivy z custom policies
- Dodano vulnerable app do testów
- Dodano CI/CD pipeline (GitHub Actions)
- Dodano skrypty automatyzacji i Makefile
- Dodano dokumentację (README, TESTING)"
```

## Krok 3: Sprawdzenie remote

```bash
# Sprawdź czy masz skonfigurowany remote
git remote -v

# Jeśli nie masz remote, dodaj go:
# git remote add origin https://github.com/TWOJA_NAZWA_UZYTKOWNIKA/AutoHealKube.git
# LUB
# git remote add origin git@github.com:TWOJA_NAZWA_UZYTKOWNIKA/AutoHealKube.git
```

## Krok 4: Wypchnięcie do GitHub

### Jeśli to pierwszy push
```bash
# Ustawienie upstream i push
git push -u origin main
```

### Jeśli już masz remote
```bash
# Zwykły push
git push origin main

# Lub jeśli jesteś na branchu main i masz ustawiony upstream:
git push
```

## Krok 5: Weryfikacja

1. Otwórz GitHub w przeglądarce: `https://github.com/TWOJA_NAZWA_UZYTKOWNIKA/AutoHealKube`
2. Sprawdź czy wszystkie pliki są widoczne
3. Sprawdź czy GitHub Actions workflow się uruchomił (zakładka "Actions")

## 🔧 Konfiguracja GitHub Actions

### Wymagane Secrets (jeśli używasz własnego registry)

Jeśli chcesz używać własnego Docker registry zamiast GitHub Container Registry:

1. Przejdź do: Settings → Secrets and variables → Actions
2. Dodaj secrets:
   - `DOCKER_USERNAME` - nazwa użytkownika
   - `DOCKER_PASSWORD` - hasło/token
   - `DOCKER_REGISTRY` - URL registry (opcjonalnie)

### Konfiguracja Kubernetes dla deploy (jeśli używasz)

Jeśli chcesz automatyczny deploy do Kubernetes z GitHub Actions:

1. Dodaj secrets:
   - `KUBECONFIG` - zawartość pliku kubeconfig
   - LUB
   - `K8S_CLUSTER_URL` - URL klastra
   - `K8S_TOKEN` - token Kubernetes
   - `K8S_CA_CERT` - certyfikat CA

## 📝 Tworzenie nowego repozytorium na GitHub (jeśli jeszcze nie istnieje)

### Metoda 1: Przez GitHub Web UI

1. Przejdź do https://github.com/new
2. Wpisz nazwę: `AutoHealKube`
3. Wybierz public/private
4. **NIE** zaznaczaj "Initialize with README" (już masz pliki)
5. Kliknij "Create repository"
6. Wykonaj kroki 3-4 powyżej (dodaj remote i push)

### Metoda 2: Przez GitHub CLI

```bash
# Instalacja GitHub CLI (jeśli nie masz)
# Ubuntu/Debian:
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Autoryzacja
gh auth login

# Utworzenie repo i push
gh repo create AutoHealKube --public --source=. --remote=origin --push
```

## 🔄 Aktualizacja istniejącego repozytorium

Jeśli już masz repo na GitHub i chcesz zaktualizować:

```bash
# Pobierz najnowsze zmiany (jeśli są)
git pull origin main

# Dodaj swoje zmiany
git add .
git commit -m "feat: Aktualizacja struktury projektu"

# Wypchnij
git push origin main
```

## 🏷️ Tworzenie release/tagu

```bash
# Utworzenie taga
git tag -a v1.0.0 -m "Release version 1.0.0 - Initial release"

# Wypchnięcie taga
git push origin v1.0.0
```

## ⚠️ Troubleshooting

### Problem: "Permission denied"
```bash
# Sprawdź czy masz skonfigurowany SSH key lub użyj HTTPS z tokenem
# Dla HTTPS:
git remote set-url origin https://github.com/USERNAME/AutoHealKube.git
# Będziesz musiał użyć Personal Access Token zamiast hasła
```

### Problem: "Updates were rejected"
```bash
# Pobierz najnowsze zmiany i zmerguj
git pull origin main --rebase
# Następnie push
git push origin main
```

### Problem: GitHub Actions nie działa
- Sprawdź czy plik `.github/workflows/devsecops-pipeline.yml` jest w repozytorium
- Sprawdź czy workflow ma poprawne uprawnienia (Settings → Actions → General)
- Sprawdź logi w zakładce "Actions" na GitHub

## 📚 Przydatne linki

- [GitHub Docs - Pushing to a remote](https://docs.github.com/en/get-started/using-git/pushing-commits-to-a-remote-repository)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
