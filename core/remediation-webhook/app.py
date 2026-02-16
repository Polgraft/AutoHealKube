# core/remediation-webhook/app.py - Custom webhook dla AutoHealKube remediation
# Cel: Odbiera alerty Falco (JSON), analizuje, patchuje K8s resources (np. add non-root securityContext), rollout restart.
# Użyj: uvicorn app:app --host 0.0.0.0 --port 8000 (lokalny test)
# Zależności: fastapi, uvicorn, kubernetes (zainstalowane via Ansible)
# Konfig z values.yaml: np. thresholds, actions.
# Wersja: Python 3.11+ (2026 compat), FastAPI 0.109+
# Reusable: Dostosuj rules do swoich alertów.

import os
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import logging

# Setup logging (do Loki później)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load K8s config (in-cluster dla prod, lokalnie via KUBECONFIG)
try:
    config.load_incluster_config()
except config.ConfigException:
    config.load_kube_config()  # Fallback dla local/Minikube

v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()

# Model dla Falco alert (przykładny, dostosuj do Falco output format)
class FalcoAlert(BaseModel):
    output: str  # Pełny output alertu
    priority: str  # e.g., "WARNING"
    rule: str  # e.g., "Run shell in container"
    time: str
    output_fields: dict  # Detale: container.id, proc.cmdline, etc.

app = FastAPI(title="AutoHealKube Remediation Webhook")

@app.post("/alert")
async def receive_alert(alert: FalcoAlert, request: Request):
    """
    Endpoint: Odbiera Falco alert, analizuje, remediate.
    Przykładowy payload: {"output": "Alert text", "rule": "Run shell in container", "output_fields": {"k8s.pod.name": "vuln-pod"}}
    Actions: Jeśli match rule (np. shell/exec), patch securityContext, rollout.
    """
    logger.info(f"Odebrano alert: {alert.rule} - {alert.output}")

    # Pobierz config z env (z values.yaml via Helm później)
    remediation_enabled = os.getenv("REMEDIATION_ENABLED", "true") == "true"

    if not remediation_enabled:
        raise HTTPException(status_code=200, detail="Remediation disabled")

    # Analiza: Przykładowe rules do remediation
    if "shell" in alert.rule.lower() or "exec" in alert.rule.lower():  # Match na root/shell access
        # Wyciągnij pod details z output_fields
        pod_name = alert.output_fields.get("k8s.pod.name")
        namespace = alert.output_fields.get("k8s.ns.name", "default")

        if not pod_name:
            raise HTTPException(status_code=400, detail="Brak pod_name w alert")

        logger.info(f"Remediacja dla pod: {pod_name} w ns: {namespace}")

        # Patch securityContext: Add runAsNonRoot: true do wszystkich containers
        patch_body = {
            "spec": {
                "template": {
                    "spec": {
                        "containers": [
                            {"name": "*", "securityContext": {"runAsNonRoot": True}}
                        ]
                    }
                }
            }
        }

        try:
            # Zakładaj, że pod jest częścią Deployment (znajdź owner)
            pod = v1.read_namespaced_pod(pod_name, namespace)
            if pod.metadata.owner_references:
                owner = pod.metadata.owner_references[0]
                if owner.kind == "ReplicaSet":
                    # Znajdź Deployment od RS
                    rs = apps_v1.read_namespaced_replica_set(owner.name, namespace)
                    if rs.metadata.owner_references:
                        dep_name = rs.metadata.owner_references[0].name
                        # Patch Deployment
                        apps_v1.patch_namespaced_deployment(dep_name, namespace, patch_body)
                        logger.info(f"Patched Deployment: {dep_name}")

                        # Rollout restart
                        rollout_body = {"spec": {"template": {"metadata": {"annotations": {"kubectl.kubernetes.io/restartedAt": "now"}}}}}
                        apps_v1.patch_namespaced_deployment(dep_name, namespace, rollout_body)
                        logger.info(f"Rollout restart dla {dep_name}")
            return {"status": "remediated"}

        except ApiException as e:
            logger.error(f"Błąd K8s API: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    return {"status": "no_action"}  # Jeśli no match

@app.get("/health")
async def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)