# tests/e2e/vulnerable-examples/vuln-nginx/Dockerfile - Vulnerable obraz do testów (known vuln dla Trivy block)
# WARNING: Tylko do testów! Nie deployuj w prod.
# Cel: Obraz z HIGH/CRITICAL vuln (np. old nginx z CVE).

FROM nginx:1.18  # Stara wersja z known vulns (np. CVE-2021-23017)
RUN apt-get update && apt-get install -y curl  # Dodatkowe deps dla runtime attacks
CMD ["nginx", "-g", "daemon off;"]