"""
Auto-Heal Webhook - FastAPI webhook do automatycznego naprawiania problemów
Odbiera alerty z Falco, Prometheus i innych źródeł i wykonuje akcje naprawcze.
"""
import os
import logging
from typing import Dict, Any, Optional
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from kubernetes import client, config
from remediation import RemediationEngine

# Konfiguracja logowania
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Inicjalizacja FastAPI
app = FastAPI(
    title="Auto-Heal Webhook",
    description="Webhook do automatycznego naprawiania problemów w Kubernetes",
    version="1.0.0"
)

# Inicjalizacja Kubernetes client
try:
    config.load_incluster_config()
except config.ConfigException:
    try:
        config.load_kube_config()
    except config.ConfigException:
        logger.warning("Nie można załadować konfiguracji Kubernetes")

# Inicjalizacja silnika naprawczego
remediation_engine = RemediationEngine()

# Modele danych
class FalcoEvent(BaseModel):
    """Model zdarzenia z Falco"""
    output: str
    priority: str
    rule: str
    time: str
    output_fields: Dict[str, Any]
    hostname: str
    tags: Optional[list] = []

class PrometheusAlert(BaseModel):
    """Model alertu z Prometheus"""
    status: str
    labels: Dict[str, str]
    annotations: Dict[str, str]
    startsAt: str
    endsAt: Optional[str] = None

class HealthCheck(BaseModel):
    """Model health check"""
    status: str
    message: str

@app.get("/health", response_model=HealthCheck)
async def health_check():
    """Health check endpoint"""
    return HealthCheck(status="healthy", message="Auto-heal webhook is running")

@app.post("/webhook/falco")
async def falco_webhook(event: FalcoEvent):
    """
    Webhook do odbierania zdarzeń z Falco
    """
    logger.info(f"Otrzymano zdarzenie Falco: {event.rule} - {event.priority}")
    logger.debug(f"Szczegóły zdarzenia: {event.output_fields}")
    
    try:
        # Decyzja o akcji naprawczej na podstawie reguły i priorytetu
        action = remediation_engine.decide_action(
            source="falco",
            rule=event.rule,
            priority=event.priority,
            metadata=event.output_fields
        )
        
        if action:
            result = remediation_engine.execute_action(action)
            logger.info(f"Wykonano akcję naprawczą: {action['type']} - {result}")
            return {"status": "success", "action": action, "result": result}
        else:
            logger.info("Brak akcji naprawczej dla tego zdarzenia")
            return {"status": "no_action", "message": "No remediation action required"}
    
    except Exception as e:
        logger.error(f"Błąd podczas przetwarzania zdarzenia Falco: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/webhook/prometheus")
async def prometheus_webhook(alert: PrometheusAlert):
    """
    Webhook do odbierania alertów z Prometheus Alertmanager
    """
    logger.info(f"Otrzymano alert Prometheus: {alert.labels.get('alertname', 'unknown')}")
    
    try:
        # Decyzja o akcji naprawczej na podstawie alertu
        action = remediation_engine.decide_action(
            source="prometheus",
            rule=alert.labels.get("alertname", ""),
            priority=alert.labels.get("severity", "warning"),
            metadata={
                "labels": alert.labels,
                "annotations": alert.annotations,
                "status": alert.status
            }
        )
        
        if action:
            result = remediation_engine.execute_action(action)
            logger.info(f"Wykonano akcję naprawczą: {action['type']} - {result}")
            return {"status": "success", "action": action, "result": result}
        else:
            return {"status": "no_action", "message": "No remediation action required"}
    
    except Exception as e:
        logger.error(f"Błąd podczas przetwarzania alertu Prometheus: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics")
async def metrics():
    """Endpoint dla Prometheus metrics"""
    # TODO: Implementacja metryk
    return {"metrics": "not_implemented_yet"}

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
