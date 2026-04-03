locals {
  bitmagnet = {
    namespace      = "bitmagnet"
    host           = "bitmagnet.${var.base_domain}"
    image          = "ghcr.io/bitmagnet-io/bitmagnet:v0.10.0"
    postgres_image = "postgres:16-alpine"
    crawler = {
      save_files_threshold = 25
    }
    cleanup = {
      schedule            = "17 3 * * 0"
      retention_days      = 120
      max_seeders         = 0
      delete_batch_size   = 5000
      successful_runs_ttl = 3
      failed_runs_ttl     = 3
    }
    storage = {
      config   = "2Gi"
      postgres = "64Gi"
    }
    resources = {
      requests = {
        cpu    = "250m"
        memory = "512Mi"
      }
      limits = {
        cpu    = "1"
        memory = "2Gi"
      }
    }
  }
}

resource "authentik_provider_proxy" "bitmagnet" {
  depends_on         = [helm_release.authentik]
  name               = "bitmagnet"
  external_host      = "https://${local.bitmagnet.host}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "bitmagnet" {
  name              = "bitmagnet"
  slug              = "bitmagnet-slug"
  protocol_provider = authentik_provider_proxy.bitmagnet.id
  meta_icon         = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/bitmagnet.svg"
}

resource "authentik_group" "bitmagnet_users" {
  depends_on = [helm_release.authentik]
  name       = "bitmagnet-users"
}

resource "authentik_policy_binding" "bitmagnet_access" {
  target = authentik_application.bitmagnet.uuid
  group  = authentik_group.bitmagnet_users.id
  order  = 0
}

resource "authentik_outpost_provider_attachment" "bitmagnet" {
  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.bitmagnet.id
}

resource "kubernetes_namespace" "bitmagnet" {
  metadata {
    name = local.bitmagnet.namespace
  }
}

resource "random_password" "bitmagnet_postgres_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "bitmagnet_postgres" {
  metadata {
    name      = "bitmagnet-postgres-secret"
    namespace = local.bitmagnet.namespace
  }

  data = {
    POSTGRES_PASSWORD = random_password.bitmagnet_postgres_password.result
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "bitmagnet_config" {
  metadata {
    name      = "bitmagnet-config"
    namespace = local.bitmagnet.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.bitmagnet.storage.config
      }
    }
  }
}

resource "kubernetes_stateful_set" "bitmagnet_postgres" {
  metadata {
    name      = "bitmagnet-postgres"
    namespace = local.bitmagnet.namespace
    labels = {
      app = "bitmagnet-postgres"
    }
  }
  spec {
    service_name = "bitmagnet-postgres"
    replicas     = 1
    selector {
      match_labels = {
        app = "bitmagnet-postgres"
      }
    }
    template {
      metadata {
        labels = {
          app = "bitmagnet-postgres"
        }
      }
      spec {
        container {
          name  = "postgres"
          image = local.bitmagnet.postgres_image
          port {
            name           = "postgres"
            container_port = 5432
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.bitmagnet_postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "POSTGRES_DB"
            value = "bitmagnet"
          }
          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }
          env {
            name  = "PGUSER"
            value = "postgres"
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 20
            period_seconds        = 20
            timeout_seconds       = 5
          }
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = local.bitmagnet.storage.postgres
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "bitmagnet_postgres" {
  metadata {
    name      = "bitmagnet-postgres"
    namespace = local.bitmagnet.namespace
  }
  spec {
    selector = {
      app = "bitmagnet-postgres"
    }
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_cron_job_v1" "bitmagnet_postgres_cleanup" {
  metadata {
    name      = "bitmagnet-postgres-cleanup"
    namespace = local.bitmagnet.namespace
  }

  spec {
    schedule                      = local.bitmagnet.cleanup.schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = local.bitmagnet.cleanup.successful_runs_ttl
    failed_jobs_history_limit     = local.bitmagnet.cleanup.failed_runs_ttl

    job_template {
      metadata {}

      spec {
        template {
          metadata {}

          spec {
            security_context {
              run_as_non_root = true
              run_as_user     = 70
              run_as_group    = 70
              fs_group        = 70

              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            restart_policy = "Never"

            container {
              name  = "postgres-cleanup"
              image = local.bitmagnet.postgres_image

              security_context {
                allow_privilege_escalation = false
                run_as_non_root            = true

                capabilities {
                  drop = ["ALL"]
                }
              }

              command = ["/bin/sh", "-ec"]
              args = [<<-EOT
                export PGPASSWORD="$POSTGRES_PASSWORD"
                export PGOPTIONS="-c max_parallel_maintenance_workers=0 -c max_parallel_workers_per_gather=0"

                while true; do
                  deleted="$(psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA <<SQL
                WITH doomed AS (
                  SELECT t.info_hash
                  FROM torrents t
                  WHERE t.created_at < now() - make_interval(days => ${local.bitmagnet.cleanup.retention_days})
                    AND EXISTS (
                      SELECT 1
                      FROM torrents_torrent_sources tts
                      WHERE tts.info_hash = t.info_hash
                        AND tts.seeders IS NOT NULL
                    )
                    AND NOT EXISTS (
                      SELECT 1
                      FROM torrents_torrent_sources tts
                      WHERE tts.info_hash = t.info_hash
                        AND COALESCE(tts.seeders, 0) > ${local.bitmagnet.cleanup.max_seeders}
                    )
                  ORDER BY t.updated_at NULLS LAST
                  LIMIT ${local.bitmagnet.cleanup.delete_batch_size}
                ), deleted AS (
                  DELETE FROM torrents t
                  USING doomed d
                  WHERE t.info_hash = d.info_hash
                  RETURNING 1
                )
                SELECT COUNT(*) FROM deleted;
                SQL
                )"

                  [ "$deleted" = "0" ] && break
                  sleep 1
                done

                psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM ANALYZE torrents"
                psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM ANALYZE torrents_torrent_sources"
                psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM ANALYZE torrent_files"
                psql -v ON_ERROR_STOP=1 -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM ANALYZE torrent_contents"
              EOT
              ]

              env {
                name  = "POSTGRES_HOST"
                value = kubernetes_service.bitmagnet_postgres.metadata[0].name
              }

              env {
                name  = "POSTGRES_DB"
                value = "bitmagnet"
              }

              env {
                name  = "POSTGRES_USER"
                value = "postgres"
              }

              env {
                name = "POSTGRES_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.bitmagnet_postgres.metadata[0].name
                    key  = "POSTGRES_PASSWORD"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "bitmagnet" {
  depends_on = [
    kubernetes_service.bitmagnet_postgres,
    kubernetes_persistent_volume_claim.bitmagnet_config,
  ]

  metadata {
    name      = "bitmagnet"
    namespace = local.bitmagnet.namespace
    labels = {
      app = "bitmagnet"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "bitmagnet"
      }
    }
    template {
      metadata {
        labels = {
          app = "bitmagnet"
        }
      }
      spec {
        container {
          name  = "bitmagnet"
          image = local.bitmagnet.image
          args = [
            "worker",
            "run",
            "--keys=http_server",
            "--keys=queue_server",
            "--keys=dht_crawler",
          ]
          port {
            name           = "http"
            container_port = 3333
          }
          port {
            name           = "bittorrent-tcp"
            container_port = 3334
            protocol       = "TCP"
          }
          port {
            name           = "bittorrent-udp"
            container_port = 3334
            protocol       = "UDP"
          }
          env {
            name  = "POSTGRES_HOST"
            value = kubernetes_service.bitmagnet_postgres.metadata[0].name
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.bitmagnet_postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }
          env {
            name  = "POSTGRES_DB"
            value = "bitmagnet"
          }
          env {
            name  = "DHT_CRAWLER_SAVE_FILES_THRESHOLD"
            value = tostring(local.bitmagnet.crawler.save_files_threshold)
          }
          resources {
            limits   = local.bitmagnet.resources.limits
            requests = local.bitmagnet.resources.requests
          }
          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            timeout_seconds       = 5
          }
          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 20
            period_seconds        = 20
            timeout_seconds       = 5
          }
          volume_mount {
            name       = "config"
            mount_path = "/root/.config/bitmagnet"
          }
        }
        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.bitmagnet_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "bitmagnet" {
  metadata {
    name      = "bitmagnet"
    namespace = local.bitmagnet.namespace
  }
  spec {
    selector = {
      app = "bitmagnet"
    }
    port {
      name        = "http"
      port        = 3333
      target_port = 3333
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service" "bitmagnet_bittorrent" {
  metadata {
    name      = "bitmagnet-bittorrent"
    namespace = local.bitmagnet.namespace
  }
  spec {
    selector = {
      app = "bitmagnet"
    }
    port {
      name        = "bittorrent-tcp"
      port        = 3334
      target_port = 3334
      protocol    = "TCP"
    }
    port {
      name        = "bittorrent-udp"
      port        = 3334
      target_port = 3334
      protocol    = "UDP"
    }
  }
}

resource "kubernetes_service" "bitmagnet_outpost" {
  metadata {
    name      = "bitmagnet-outpost"
    namespace = local.bitmagnet.namespace
  }
  spec {
    type          = "ExternalName"
    external_name = "ak-outpost-authentik-embedded-outpost.authentik.svc.cluster.local"
    port {
      name        = "http"
      port        = 9000
      target_port = 9000
    }
  }
}

resource "kubernetes_manifest" "bitmagnet_forward_auth" {
  depends_on = [authentik_outpost_provider_attachment.bitmagnet]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "bitmagnet-authentik-forward-auth"
      namespace = local.bitmagnet.namespace
    }
    spec = {
      forwardAuth = {
        address            = "http://${kubernetes_service.bitmagnet_outpost.metadata[0].name}.${local.bitmagnet.namespace}.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-authentik-username",
          "X-authentik-email",
          "X-authentik-groups",
          "X-authentik-entitlements",
          "X-authentik-jwt",
          "X-authentik-meta-provider",
        ]
        authResponseHeadersRegex = "^Set-Cookie$"
      }
    }
  }
}

resource "kubernetes_ingress_v1" "bitmagnet" {
  depends_on = [kubernetes_manifest.bitmagnet_forward_auth]

  metadata {
    name      = "bitmagnet"
    namespace = local.bitmagnet.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.middlewares" = "${local.bitmagnet.namespace}-${kubernetes_manifest.bitmagnet_forward_auth.manifest.metadata.name}@kubernetescrd"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.bitmagnet.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.bitmagnet.metadata[0].name
              port {
                number = 3333
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "bitmagnet-tls"
      hosts       = [local.bitmagnet.host]
    }
  }
}

resource "kubernetes_ingress_v1" "bitmagnet_outpost" {
  metadata {
    name      = "bitmagnet-outpost"
    namespace = local.bitmagnet.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.bitmagnet.host

      http {
        path {
          path      = "/outpost.goauthentik.io/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.bitmagnet_outpost.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "bitmagnet-tls"
      hosts       = [local.bitmagnet.host]
    }
  }
}
