"""
Silnik naprawczy - wykonuje automatyczne akcje naprawcze w Kubernetes
"""
import logging
from typing import Dict, Any, Optional, List
from kubernetes import client, config
from kubernetes.client.rest import ApiException

logger = logging.getLogger(__name__)

class RemediationEngine:
    """Silnik do wykonywania akcji naprawczych"""
    
    def __init__(self):
        """Inicjalizacja silnika naprawczego"""
        try:
            config.load_incluster_config()
        except config.ConfigException:
            try:
                config.load_kube_config()
            except config.ConfigException:
                logger.warning("Nie można załadować konfiguracji Kubernetes")
        
        self.apps_v1 = client.AppsV1Api()
        self.core_v1 = client.CoreV1Api()
        self.batch_v1 = client.BatchV1Api()
        
        # Mapowanie reguł na akcje
        self.action_rules = {
            "falco": {
                "Container Escape Attempt": {
                    "action": "delete_pod",
                    "priority_threshold": "CRITICAL"
                },
                "Privilege Escalation Attempt": {
                    "action": "delete_pod",
                    "priority_threshold": "ERROR"
                },
                "Unauthorized Process Execution": {
                    "action": "restart_pod",
                    "priority_threshold": "WARNING"
                }
            },
            "prometheus": {
                "PodCrashLooping": {
                    "action": "restart_deployment",
                    "priority_threshold": "critical"
                },
                "HighMemoryUsage": {
                    "action": "scale_down",
                    "priority_threshold": "warning"
                },
                "HighCPUUsage": {
                    "action": "scale_down",
                    "priority_threshold": "warning"
                }
            }
        }
    
    def decide_action(
        self,
        source: str,
        rule: str,
        priority: str,
        metadata: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        Decyduje o akcji naprawczej na podstawie zdarzenia
        
        Args:
            source: Źródło zdarzenia (falco, prometheus)
            rule: Nazwa reguły/alertu
            priority: Priorytet zdarzenia
            metadata: Dodatkowe metadane zdarzenia
        
        Returns:
            Słownik z akcją do wykonania lub None
        """
        logger.info(f"Analizowanie zdarzenia: {source}/{rule} ({priority})")
        
        # Sprawdzenie czy istnieje reguła dla tego zdarzenia
        if source not in self.action_rules:
            logger.debug(f"Brak reguł dla źródła: {source}")
            return None
        
        if rule not in self.action_rules[source]:
            logger.debug(f"Brak reguły dla: {rule}")
            return None
        
        rule_config = self.action_rules[source][rule]
        
        # Sprawdzenie priorytetu
        if not self._check_priority(priority, rule_config.get("priority_threshold", "INFO")):
            logger.debug(f"Priorytet {priority} nie spełnia wymagań")
            return None
        
        # Przygotowanie akcji
        action = {
            "type": rule_config["action"],
            "source": source,
            "rule": rule,
            "priority": priority,
            "metadata": metadata
        }
        
        # Ekstrakcja informacji o zasobie z metadanych
        namespace = metadata.get("k8s.ns.name") or metadata.get("namespace", "default")
        pod_name = metadata.get("k8s.pod.name") or metadata.get("pod")
        container_name = metadata.get("k8s.container.name") or metadata.get("container")
        deployment_name = metadata.get("k8s.deployment.name") or metadata.get("deployment")
        
        action["namespace"] = namespace
        action["pod_name"] = pod_name
        action["container_name"] = container_name
        action["deployment_name"] = deployment_name
        
        return action
    
    def _check_priority(self, priority: str, threshold: str) -> bool:
        """Sprawdza czy priorytet spełnia próg"""
        priority_levels = {
            "CRITICAL": 4,
            "ERROR": 3,
            "WARNING": 2,
            "NOTICE": 1,
            "INFO": 0,
            "critical": 4,
            "error": 3,
            "warning": 2,
            "info": 0
        }
        
        priority_val = priority_levels.get(priority.upper(), 0)
        threshold_val = priority_levels.get(threshold.upper(), 0)
        
        return priority_val >= threshold_val
    
    def execute_action(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """
        Wykonuje akcję naprawczą
        
        Args:
            action: Słownik z akcją do wykonania
        
        Returns:
            Wynik wykonania akcji
        """
        action_type = action["type"]
        namespace = action.get("namespace", "default")
        
        logger.info(f"Wykonywanie akcji: {action_type} w namespace {namespace}")
        
        try:
            if action_type == "delete_pod":
                return self._delete_pod(action)
            elif action_type == "restart_pod":
                return self._restart_pod(action)
            elif action_type == "restart_deployment":
                return self._restart_deployment(action)
            elif action_type == "scale_down":
                return self._scale_down(action)
            elif action_type == "scale_up":
                return self._scale_up(action)
            elif action_type == "rollback":
                return self._rollback_deployment(action)
            else:
                logger.warning(f"Nieznany typ akcji: {action_type}")
                return {"status": "error", "message": f"Unknown action type: {action_type}"}
        
        except ApiException as e:
            logger.error(f"Błąd Kubernetes API: {e}")
            return {"status": "error", "message": str(e)}
        except Exception as e:
            logger.error(f"Błąd podczas wykonywania akcji: {e}")
            return {"status": "error", "message": str(e)}
    
    def _delete_pod(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Usuwa pod"""
        pod_name = action.get("pod_name")
        namespace = action.get("namespace", "default")
        
        if not pod_name:
            return {"status": "error", "message": "Pod name not provided"}
        
        try:
            self.core_v1.delete_namespaced_pod(
                name=pod_name,
                namespace=namespace,
                grace_period_seconds=0
            )
            logger.info(f"Usunięto pod: {pod_name} w namespace {namespace}")
            return {"status": "success", "action": "deleted", "pod": pod_name}
        except ApiException as e:
            if e.status == 404:
                logger.warning(f"Pod {pod_name} nie istnieje")
                return {"status": "not_found", "pod": pod_name}
            raise
    
    def _restart_pod(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Restartuje pod poprzez usunięcie"""
        return self._delete_pod(action)
    
    def _restart_deployment(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Restartuje deployment"""
        deployment_name = action.get("deployment_name")
        namespace = action.get("namespace", "default")
        
        if not deployment_name:
            # Próba znalezienia deploymentu na podstawie poda
            pod_name = action.get("pod_name")
            if pod_name:
                deployment_name = self._find_deployment_for_pod(pod_name, namespace)
        
        if not deployment_name:
            return {"status": "error", "message": "Deployment name not found"}
        
        try:
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=namespace
            )
            
            # Restart poprzez zmianę annotation
            if deployment.spec.template.metadata.annotations is None:
                deployment.spec.template.metadata.annotations = {}
            
            import time
            deployment.spec.template.metadata.annotations["kubectl.kubernetes.io/restartedAt"] = str(int(time.time()))
            
            self.apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            
            logger.info(f"Restartowano deployment: {deployment_name} w namespace {namespace}")
            return {"status": "success", "action": "restarted", "deployment": deployment_name}
        
        except ApiException as e:
            if e.status == 404:
                return {"status": "not_found", "deployment": deployment_name}
            raise
    
    def _scale_down(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Zmniejsza liczbę replik"""
        deployment_name = action.get("deployment_name")
        namespace = action.get("namespace", "default")
        
        if not deployment_name:
            return {"status": "error", "message": "Deployment name not found"}
        
        try:
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=namespace
            )
            
            current_replicas = deployment.spec.replicas or 1
            new_replicas = max(1, current_replicas - 1)
            
            deployment.spec.replicas = new_replicas
            self.apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            
            logger.info(f"Zmniejszono repliki deploymentu {deployment_name} z {current_replicas} do {new_replicas}")
            return {
                "status": "success",
                "action": "scaled_down",
                "deployment": deployment_name,
                "replicas": new_replicas
            }
        except ApiException as e:
            if e.status == 404:
                return {"status": "not_found", "deployment": deployment_name}
            raise
    
    def _scale_up(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Zwiększa liczbę replik"""
        deployment_name = action.get("deployment_name")
        namespace = action.get("namespace", "default")
        
        if not deployment_name:
            return {"status": "error", "message": "Deployment name not found"}
        
        try:
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=namespace
            )
            
            current_replicas = deployment.spec.replicas or 1
            new_replicas = min(10, current_replicas + 1)  # Max 10 replik
            
            deployment.spec.replicas = new_replicas
            self.apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            
            logger.info(f"Zwiększono repliki deploymentu {deployment_name} z {current_replicas} do {new_replicas}")
            return {
                "status": "success",
                "action": "scaled_up",
                "deployment": deployment_name,
                "replicas": new_replicas
            }
        except ApiException as e:
            if e.status == 404:
                return {"status": "not_found", "deployment": deployment_name}
            raise
    
    def _rollback_deployment(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Wykonuje rollback deploymentu"""
        deployment_name = action.get("deployment_name")
        namespace = action.get("namespace", "default")
        
        if not deployment_name:
            return {"status": "error", "message": "Deployment name not found"}
        
        try:
            # Pobranie historii deploymentu
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=namespace
            )
            
            # Rollback do poprzedniej wersji
            rollback = client.AppsV1Api()
            rollback.create_namespaced_deployment_rollback(
                name=deployment_name,
                namespace=namespace,
                body={
                    "name": deployment_name,
                    "rollbackTo": {
                        "revision": 0  # 0 oznacza poprzednią wersję
                    }
                }
            )
            
            logger.info(f"Wykonano rollback deploymentu: {deployment_name}")
            return {"status": "success", "action": "rolled_back", "deployment": deployment_name}
        
        except ApiException as e:
            if e.status == 404:
                return {"status": "not_found", "deployment": deployment_name}
            raise
    
    def _find_deployment_for_pod(self, pod_name: str, namespace: str) -> Optional[str]:
        """Znajduje deployment dla poda"""
        try:
            pod = self.core_v1.read_namespaced_pod(name=pod_name, namespace=namespace)
            labels = pod.metadata.labels
            
            # Szukanie deploymentu na podstawie etykiet
            if labels:
                for key, value in labels.items():
                    if key == "app" or key.startswith("app.kubernetes.io/name"):
                        deployments = self.apps_v1.list_namespaced_deployment(
                            namespace=namespace,
                            label_selector=f"{key}={value}"
                        )
                        if deployments.items:
                            return deployments.items[0].metadata.name
        except Exception as e:
            logger.error(f"Błąd podczas szukania deploymentu: {e}")
        
        return None
