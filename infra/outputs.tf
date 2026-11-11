output "namespace" {
  description = "Namespace containing all WMS resources."
  value       = kubernetes_namespace_v1.wms.metadata[0].name
}

output "frontend_service" {
  description = "Frontend NodePort service name."
  value       = kubernetes_service_v1.frontend.metadata[0].name
}

output "frontend_node_port" {
  description = "NodePort assigned to the frontend."
  value       = kubernetes_service_v1.frontend.spec[0].port[0].node_port
}

output "open_frontend_command" {
  description = "Command that opens the WMS frontend in Minikube."
  value       = "minikube service ${kubernetes_service_v1.frontend.metadata[0].name} -n ${kubernetes_namespace_v1.wms.metadata[0].name}"
}

output "prometheus_service" {
  description = "Prometheus NodePort service name."
  value       = kubernetes_service_v1.prometheus.metadata[0].name
}

output "prometheus_node_port" {
  description = "NodePort assigned to Prometheus."
  value       = kubernetes_service_v1.prometheus.spec[0].port[0].node_port
}

output "open_prometheus_command" {
  description = "Command that opens Prometheus in Minikube."
  value       = "minikube service ${kubernetes_service_v1.prometheus.metadata[0].name} -n ${kubernetes_namespace_v1.wms.metadata[0].name}"
}
