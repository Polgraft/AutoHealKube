# Cel: Obraz z HIGH/CRITICAL vuln (np. old nginx z CVE)
# Stara wersja nginx + dodatkowe narzędzia do testów runtime

FROM nginx:1.18

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

CMD ["nginx", "-g", "daemon off;"]
