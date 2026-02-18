# Celowo podatny obraz Docker do testów bezpieczeństwa
# ⚠️ NIE UŻYWAJ W PRODUKCJI!

FROM python:3.11-slim

# Celowo uruchamiamy jako root (podatność)
USER root

WORKDIR /app

# Kopiowanie requirements i instalacja
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Kopiowanie aplikacji
COPY main.py .

# Celowo brak healthcheck (podatność)
# Celowo brak limitów zasobów (podatność)

# Uruchomienie jako root
CMD ["python", "main.py"]
