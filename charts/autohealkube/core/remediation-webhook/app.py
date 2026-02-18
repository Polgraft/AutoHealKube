# core/remediation-webhook/app.py - Custom webhook dla AutoHealKube remediation
# Cel: Odbiera alerty Falco (JSON), analizuje, patchuje K8s resources (np. add non-root securityContext), rollout restart.
# Użyj: uvicorn app:app --host 0.0.0.0 --port 8000 (lokalny test)
# Zależności: fastapi, uvicorn, kubernetes (zainstalowane via Ansible)
# Konfig z values.yaml: np. thresholds, actions.
# Wersja: Python 3.11+ (2026 compat), FastAPI 0.109+
# Reusable: Dostosuj rules do swoich alertów.

import os
import secrets
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
auth_v1 = client.AuthenticationV1Api()


def _extract_bearer_token(request: Request) -> str | None:
    auth = request.headers.get("authorization") or request.headers.get("Authorization")
    if not auth:
        return None
    parts = auth.split(" ", 1)
    if len(parts) != 2:
        return None
    scheme, token = parts[0].strip(), parts[1].strip()
    if scheme.lower() != "bearer" or not token:
        return None
    return token


def _require_auth(request: Request) -> None:
    """
    Auth modes:
      - off: no auth (ONLY for local debugging)
      - shared-secret: verify Authorization: Bearer <token> == WEBHOOK_BEARER_TOKEN
      - tokenreview: call Kubernetes TokenReview and allow only specific serviceaccounts
    """
    mode = os.getenv("WEBHOOK_AUTH_MODE", "shared-secret").strip().lower()
    if mode == "off":
        return

    token = _extract_bearer_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")

    if mode == "shared-secret":
        expected = os.getenv("WEBHOOK_BEARER_TOKEN", "")
        if not expected:
            logger.error("WEBHOOK_AUTH_MODE=shared-secret but WEBHOOK_BEARER_TOKEN is not set")
            raise HTTPException(status_code=503, detail="Webhook auth misconfigured")
        if not secrets.compare_digest(token, expected):
            raise HTTPException(status_code=403, detail="Invalid token")
        return

    if mode == "tokenreview":
        # Restrict who can call this webhook (default: only Falco namespace serviceaccounts).
        allowed_sas_env = os.getenv(
            "WEBHOOK_ALLOWED_SERVICEACCOUNTS",
            "system:serviceaccount:falco:falco,system:serviceaccount:falco:falco-sa",
        )
        allowed_sas = {s.strip() for s in allowed_sas_env.split(",") if s.strip()}

        try:
            review = client.V1TokenReview(spec=client.V1TokenReviewSpec(token=token))
            resp = auth_v1.create_token_review(review)
        except Exception as e:
            logger.error(f"TokenReview failed: {e}")
            raise HTTPException(status_code=503, detail="Auth backend unavailable")

        if not resp.status or not resp.status.authenticated:
            raise HTTPException(status_code=403, detail="Unauthenticated token")

        username = (resp.status.user or {}).get("username") if isinstance(resp.status.user, dict) else getattr(resp.status.user, "username", None)
        if not username or username not in allowed_sas:
            raise HTTPException(status_code=403, detail="Caller not allowed")
        return

    raise HTTPException(status_code=500, detail="Unknown auth mode")

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
    _require_auth(request)
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


