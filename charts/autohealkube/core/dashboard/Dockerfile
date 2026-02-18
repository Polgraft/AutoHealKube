# core/dashboard/Dockerfile - Build obrazu dla HTMX dashboard
# Base: Python 3.11-slim (2026 compat)
# Użyj: docker build -t autohealkube-dashboard:latest .
# Run: docker run -p 8080:8080 -e LOKI_URL=http://loki:3100 autohealkube-dashboard:latest

FROM python:3.11-slim AS builder

# Aktualizuj system i pip przed instalacją deps (fix dla CVE-2026-0861 w glibc)
RUN apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip install --upgrade pip wheel setuptools

# Instal deps i przygotuj katalog static dla HTMX/CSS
WORKDIR /app
COPY app.py .
RUN mkdir -p static && pip install --no-cache-dir --upgrade fastapi uvicorn httpx

# Final stage
FROM python:3.11-slim

# Aktualizuj system w finalnym obrazie (fix dla CVE-2026-0861)
RUN apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app .
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Expose port
EXPOSE 8080

# Run app (przez python -m, żeby nie polegać na skrypcie uvicorn w PATH)
CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]