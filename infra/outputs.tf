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
  value       = var.frontend_service_type == "NodePort" ? kubernetes_service_v1.frontend.spec[0].port[0].node_port : null
}

output "open_frontend_command" {
  description = "Command that opens the WMS frontend in Minikube."
  value       = var.frontend_service_type == "NodePort" ? "minikube service ${kubernetes_service_v1.frontend.metadata[0].name} -n ${kubernetes_namespace_v1.wms.metadata[0].name}" : null
}

output "frontend_load_balancer_hostname" {
  description = "Public AWS load balancer hostname when the frontend uses LoadBalancer."
  value       = try(kubernetes_service_v1.frontend.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "prometheus_service" {
  description = "Prometheus NodePort service name."
  value       = kubernetes_service_v1.prometheus.metadata[0].name
}

output "prometheus_node_port" {
  description = "NodePort assigned to Prometheus."
  value       = var.prometheus_service_type == "NodePort" ? kubernetes_service_v1.prometheus.spec[0].port[0].node_port : null
}

output "open_prometheus_command" {
  description = "Command that opens Prometheus in Minikube."
  value       = var.prometheus_service_type == "NodePort" ? "minikube service ${kubernetes_service_v1.prometheus.metadata[0].name} -n ${kubernetes_namespace_v1.wms.metadata[0].name}" : "kubectl port-forward service/${kubernetes_service_v1.prometheus.metadata[0].name} 9090:9090 -n ${kubernetes_namespace_v1.wms.metadata[0].name}"
}
