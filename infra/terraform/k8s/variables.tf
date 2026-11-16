variable "namespace" {
  description = "Kubernetes namespace for the WMS stack."
  type        = string
  default     = "wms"
}

variable "backend_image" {
  description = "Initial backend image. Null uses <ECR wms-backend>:latest. CI changes the tag afterwards."
  type        = string
  default     = null
  nullable    = true
}

variable "frontend_image" {
  description = "Initial frontend image. Null uses <ECR wms-frontend>:latest. CI changes the tag afterwards."
  type        = string
  default     = null
  nullable    = true
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
  default     = "5Gi"
}

variable "create_gp3_storage_class" {
  description = "Create the AWS EBS CSI gp3 StorageClass used by the database PVC."
  type        = bool
  default     = true
}

variable "database_storage_class_name" {
  description = "StorageClass assigned to the database PVC. Null uses the cluster default."
  type        = string
  default     = "wms-gp3"
  nullable    = true
}

variable "frontend_service_type" {
  description = "Kubernetes Service type used to expose the frontend."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["NodePort", "LoadBalancer"], var.frontend_service_type)
    error_message = "frontend_service_type must be NodePort or LoadBalancer."
  }
}

variable "frontend_load_balancer_source_ranges" {
  description = "Optional CIDR ranges allowed to reach the frontend LoadBalancer. Null = public."
  type        = list(string)
  default     = null
  nullable    = true
}

variable "frontend_node_port" {
  description = "NodePort of the frontend when frontend_service_type = NodePort."
  type        = number
  default     = 30080

  validation {
    condition     = var.frontend_node_port >= 30000 && var.frontend_node_port <= 32767
    error_message = "frontend_node_port must be in the Kubernetes NodePort range (30000-32767)."
  }
}

variable "prometheus_node_port" {
  description = "NodePort of Prometheus when prometheus_service_type = NodePort."
  type        = number
  default     = 30091

  validation {
    condition     = var.prometheus_node_port >= 30000 && var.prometheus_node_port <= 32767
    error_message = "prometheus_node_port must be in the Kubernetes NodePort range (30000-32767)."
  }
}

variable "prometheus_service_type" {
  description = "Kubernetes Service type used for Prometheus (LoadBalancer exposes the UI publicly)."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.prometheus_service_type)
    error_message = "prometheus_service_type must be ClusterIP, NodePort or LoadBalancer."
  }
}
