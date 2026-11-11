variable "kube_config_path" {
  description = "Path to the kubeconfig used by the Kubernetes provider."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context where WMS resources are created."
  type        = string
  default     = "minikube"
}

variable "namespace" {
  description = "Kubernetes namespace for the WMS stack."
  type        = string
  default     = "wms"
}

variable "backend_image" {
  description = "Container image used by the backend Deployment."
  type        = string
  default     = "wms-backend:local"
}

variable "frontend_image" {
  description = "Container image used by the frontend Deployment."
  type        = string
  default     = "wms-frontend:local"
}

variable "postgres_image" {
  description = "Container image used by the PostgreSQL StatefulSet."
  type        = string
  default     = "postgres:16-alpine"
}

variable "prometheus_image" {
  description = "Prometheus image used by the monitoring Deployment."
  type        = string
  default     = "prom/prometheus:v3.5.0"
}

variable "postgres_database" {
  description = "PostgreSQL database name."
  type        = string
  default     = "wms"
}

variable "postgres_user" {
  description = "PostgreSQL user name."
  type        = string
  default     = "postgres"
}

variable "postgres_password" {
  description = "PostgreSQL password. Supply it with TF_VAR_postgres_password; never commit it."
  type        = string
  sensitive   = true
}

variable "database_storage_size" {
  description = "Persistent volume size requested by PostgreSQL."
  type        = string
  default     = "1Gi"
}

variable "frontend_node_port" {
  description = "NodePort used to expose the frontend from Minikube."
  type        = number
  default     = 30080

  validation {
    condition     = var.frontend_node_port >= 30000 && var.frontend_node_port <= 32767
    error_message = "frontend_node_port must be in the Kubernetes NodePort range (30000-32767)."
  }
}

variable "prometheus_node_port" {
  description = "NodePort used to expose the Prometheus UI from Minikube."
  type        = number
  default     = 30091

  validation {
    condition     = var.prometheus_node_port >= 30000 && var.prometheus_node_port <= 32767
    error_message = "prometheus_node_port must be in the Kubernetes NodePort range (30000-32767)."
  }
}
