# Przykładowy bezpieczny obraz Docker
FROM python:3.11-slim

# Ustawienie użytkownika niebędącego rootem
RUN useradd -m -u 1000 appuser && \
    mkdir -p /app && \
    chown -R appuser:appuser /app

WORKDIR /app

# Kopiowanie requirements i instalacja zależności
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Kopiowanie aplikacji
COPY . .

# Zmiana właściciela
RUN chown -R appuser:appuser /app

# Przełączenie na użytkownika niebędącego rootem
USER appuser

# Port aplikacji
EXPOSE 8000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

# Uruchomienie aplikacji
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
