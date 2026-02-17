job "rabbitmq" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel     = 1
    health_check     = "task_states"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "app" {
    count = 1

    network {
      port "amqp"  { to = 5672 }
      port "mgmt"  { to = 15672 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "rabbitmq:3-management-alpine"
        ports = ["amqp", "mgmt"]
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name         = "rabbitmq"
        port         = "mgmt"
        address_mode = "host"
        tags         = ["management", "http"]
        check {
          type          = "http"
          path          = "/api/overview"
          interval      = "15s"
          timeout       = "5s"
          address_mode  = "host"
          header {
            Authorization = ["Basic Z3Vlc3Q6Z3Vlc3Q="]
          }
        }
      }
    }
  }
}