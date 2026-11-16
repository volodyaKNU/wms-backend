output "namespace" {
  description = "Namespace containing all WMS resources."
  value       = kubernetes_namespace_v1.wms.metadata[0].name
}

output "frontend_load_balancer_hostname" {
  description = "Public AWS load balancer hostname of the WMS UI."
  value       = try(kubernetes_service_v1.frontend.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "frontend_url" {
  description = "Public URL of the WMS UI."
  value       = try("http://${kubernetes_service_v1.frontend.status[0].load_balancer[0].ingress[0].hostname}/", null)
}

output "prometheus_load_balancer_hostname" {
  description = "Public AWS load balancer hostname of Prometheus."
  value       = try(kubernetes_service_v1.prometheus.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "prometheus_url" {
  description = "Public URL of the Prometheus UI."
  value       = try("http://${kubernetes_service_v1.prometheus.status[0].load_balancer[0].ingress[0].hostname}:9090/", null)
}
