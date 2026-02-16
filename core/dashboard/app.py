# core/dashboard/app.py - HTMX dashboard dla ostatnich incydentów AutoHealKube
# Cel: Wizualizuj logs z Loki (alerty, remediation), refresh via HTMX.
# Użyj: uvicorn app:app --port 8080
# Zależności: fastapi, httpx (dla query Loki), htmx via CDN.
# Reusable: Query последние incydenty.

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
import httpx
import os

app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")  # Jeśli masz static/ dla CSS

LOKI_URL = os.getenv("LOKI_URL", "http://loki.monitoring.svc:3100")  # Service URL

@app.get("/", response_class=HTMLResponse)
async def dashboard():
    return """
    <!doctype html>
    <html>
    <head>
        <title>AutoHealKube Dashboard</title>
        <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    </head>
    <body>
        <h1>Ostatnie Incydenty</h1>
        <div id="incidents" hx-get="/incidents" hx-trigger="every 10s" hx-swap="innerHTML"></div>
    </body>
    </html>
    """

@app.get("/incidents")
async def get_incidents():
    # Query Loki dla logs (przykładowo label {job="falco"} |~ "alert")
    async with httpx.AsyncClient() as client:
        query = '{job="falco"} |~ "alert|remediation"'  # Dostosuj
        response = await client.get(f"{LOKI_URL}/loki/api/v1/query_range?query={query}&limit=10")
        data = response.json()
        incidents = data.get('data', {}).get('result', [])
    
    html = "<ul>"
    for inc in incidents:
        html += f"<li>{inc['values'][0][1]}</li>"  # Timestamp + log
    html += "</ul>"
    return HTMLResponse(html)