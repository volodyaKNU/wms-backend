locals {
  common_labels = {
    "app.kubernetes.io/part-of"    = "wms"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_namespace_v1" "wms" {
  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

resource "kubernetes_config_map_v1" "wms" {
  metadata {
    name      = "wms-config"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    POSTGRES_DB   = var.postgres_database
    POSTGRES_USER = var.postgres_user
  }
}

resource "kubernetes_config_map_v1" "database_init" {
  metadata {
    name      = "wms-db-init"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "01-schema.sql" = file("${path.module}/schema.sql")
  }
}

resource "kubernetes_config_map_v1" "frontend_nginx" {
  metadata {
    name      = "wms-frontend-nginx"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "default.conf" = <<-NGINX
      server {
        listen 80;
        server_name _;

        root /usr/share/nginx/html;
        index index.html;

        location / {
          try_files $uri $uri/ /index.html;
        }

        location /api/ {
          proxy_pass http://wms-backend-service:4000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        }
      }
    NGINX
  }
}

resource "kubernetes_secret_v1" "database" {
  metadata {
    name      = "wms-db-secret"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = local.common_labels
  }

  type = "Opaque"

  data = {
    POSTGRES_PASSWORD = var.postgres_password
  }
}

resource "kubernetes_service_v1" "database" {
  metadata {
    name      = "wms-db-service"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-db" })
  }

  spec {
    cluster_ip = "None"
    selector = {
      app = "wms-db"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_gp3_storage_class ? 1 : 0

  metadata {
    name = "wms-gp3"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "storage"
    })
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "database" {
  metadata {
    name      = "wms-db-data"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.database_storage_class_name

    resources {
      requests = {
        storage = var.database_storage_size
      }
    }
  }

  wait_until_bound = false

  depends_on = [kubernetes_storage_class_v1.gp3]
}

resource "kubernetes_stateful_set_v1" "database" {
  metadata {
    name      = "wms-db"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-db" })
  }

  spec {
    service_name = kubernetes_service_v1.database.metadata[0].name
    replicas     = 1

    selector {
      match_labels = {
        app = "wms-db"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { app = "wms-db" })
      }

      spec {
        container {
          name              = "postgres"
          image             = var.postgres_image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name = "POSTGRES_DB"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wms.metadata[0].name
                key  = "POSTGRES_DB"
              }
            }
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wms.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.database.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 6
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            }
            initial_delay_seconds = 20
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "init-schema"
            mount_path = "/docker-entrypoint-initdb.d"
            read_only  = true
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.database.metadata[0].name
          }
        }

        volume {
          name = "init-schema"
          config_map {
            name = kubernetes_config_map_v1.database_init.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "backend" {
  metadata {
    name      = "wms-backend-service"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-backend" })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "wms-backend"
    }

    port {
      name        = "http"
      port        = 4000
      target_port = "http"
    }
  }
}

resource "kubernetes_deployment_v1" "backend" {
  metadata {
    name      = "wms-backend"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-backend" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wms-backend"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { app = "wms-backend" })
      }

      spec {
        container {
          name              = "backend"
          image             = var.backend_image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = 4000
          }

          env {
            name  = "PORT"
            value = "4000"
          }

          env {
            name  = "PGHOST"
            value = kubernetes_service_v1.database.metadata[0].name
          }

          env {
            name  = "PGPORT"
            value = "5432"
          }

          env {
            name = "PGDATABASE"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wms.metadata[0].name
                key  = "POSTGRES_DB"
              }
            }
          }

          env {
            name = "PGUSER"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wms.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }

          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.database.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          startup_probe {
            http_get {
              path = "/health/ready"
              port = "http"
            }
            period_seconds    = 2
            timeout_seconds   = 3
            failure_threshold = 30
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = "http"
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 3
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 3
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_stateful_set_v1.database]
}

resource "kubernetes_config_map_v1" "prometheus" {
  metadata {
    name      = "wms-prometheus-config"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "prometheus.yml" = <<-YAML
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      scrape_configs:
        - job_name: wms-backend
          metrics_path: /metrics
          static_configs:
            - targets:
                - wms-backend-service:4000
    YAML
  }
}

resource "kubernetes_service_v1" "prometheus" {
  metadata {
    name      = "wms-prometheus-service"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-prometheus" })
  }

  spec {
    type = var.prometheus_service_type
    selector = {
      app = "wms-prometheus"
    }

    port {
      name        = "http"
      port        = 9090
      target_port = "http"
      node_port   = var.prometheus_service_type == "NodePort" ? var.prometheus_node_port : null
    }
  }
}

resource "kubernetes_deployment_v1" "prometheus" {
  metadata {
    name      = "wms-prometheus"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-prometheus" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wms-prometheus"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { app = "wms-prometheus" })
      }

      spec {
        container {
          name              = "prometheus"
          image             = var.prometheus_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
          ]

          port {
            name           = "http"
            container_port = 9090
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus/prometheus.yml"
            sub_path   = "prometheus.yml"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.prometheus.metadata[0].name
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.backend]
}

resource "kubernetes_service_v1" "frontend" {
  metadata {
    name      = "wms-frontend-service"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-frontend" })
  }

  spec {
    type                        = var.frontend_service_type
    load_balancer_source_ranges = var.frontend_service_type == "LoadBalancer" ? var.frontend_load_balancer_source_ranges : null
    selector = {
      app = "wms-frontend"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      node_port   = var.frontend_service_type == "NodePort" ? var.frontend_node_port : null
    }
  }
}

resource "kubernetes_deployment_v1" "frontend" {
  metadata {
    name      = "wms-frontend"
    namespace = kubernetes_namespace_v1.wms.metadata[0].name
    labels    = merge(local.common_labels, { app = "wms-frontend" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wms-frontend"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { app = "wms-frontend" })
      }

      spec {
        container {
          name              = "frontend"
          image             = var.frontend_image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = 80
          }

          startup_probe {
            http_get {
              path = "/"
              port = "http"
            }
            period_seconds    = 2
            failure_threshold = 30
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 3
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 3
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/conf.d/default.conf"
            sub_path   = "default.conf"
            read_only  = true
          }
        }

        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map_v1.frontend_nginx.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.backend]
}
