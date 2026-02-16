# core/remediation-webhook/Dockerfile - Build obrazu dla webhook
# Base: Python 3.11-slim (2026 compat)
# Użyj: docker build -t autohealkube-webhook:latest .
# Run: docker run -p 8000:8000 -e REMEDIATION_ENABLED=true autohealkube-webhook:latest

FROM python:3.11-slim AS builder

# Instal deps
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir fastapi uvicorn kubernetes pydantic

# Final stage
FROM python:3.11-slim

WORKDIR /app
COPY --from=builder /app .
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages

# Expose port
EXPOSE 8000

# Run app
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]