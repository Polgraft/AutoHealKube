#!/bin/bash
# Skrypt do wypchnięcia zmian do GitHub

set -e

echo "🚀 AutoHealKube - Wypychanie do GitHub"

# Sprawdzenie czy jesteśmy w repozytorium git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ To nie jest repozytorium git!"
    exit 1
fi

# Sprawdzenie remote
if ! git remote get-url origin > /dev/null 2>&1; then
    echo "❌ Brak skonfigurowanego remote 'origin'"
    echo "💡 Użyj: git remote add origin <URL>"
    exit 1
fi

echo "✅ Remote: $(git remote get-url origin)"

# Sprawdzenie statusu
echo ""
echo "📊 Status zmian:"
git status --short

# Pytanie o kontynuację
read -p "Czy chcesz kontynuować? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Anulowano"
    exit 1
fi

# Dodanie wszystkich plików
echo ""
echo "📦 Dodawanie plików..."
git add .

# Commit
echo ""
read -p "Wpisz komunikat commita (lub naciśnij Enter dla domyślnego): " commit_msg
if [ -z "$commit_msg" ]; then
    commit_msg="feat: Aktualizacja struktury AutoHealKube

- Dodano kompletny Helm umbrella chart
- Dodano auto-heal webhook (FastAPI)
- Dodano reguły Falco i polityki Kyverno
- Dodano CI/CD pipeline
- Dodano dokumentację i skrypty testowe"
fi

echo ""
echo "💾 Tworzenie commita..."
git commit -m "$commit_msg"

# Push
echo ""
echo "📤 Wypychanie do GitHub..."
current_branch=$(git branch --show-current)
echo "Branch: $current_branch"

read -p "Czy wypchnąć do origin/$current_branch? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push origin "$current_branch"
    echo ""
    echo "✅ Wypchnięto pomyślnie!"
    echo ""
    echo "🔗 Repozytorium: $(git remote get-url origin)"
    echo "📝 Sprawdź GitHub Actions: $(git remote get-url origin | sed 's/\.git$//')/actions"
else
    echo "❌ Anulowano push"
    echo "💡 Możesz wypchnąć ręcznie: git push origin $current_branch"
fi
