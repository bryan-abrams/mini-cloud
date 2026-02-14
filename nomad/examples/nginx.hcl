job "example" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    count = 1
    network {
      # Map dynamic port to container port 80 so nginx receives traffic
      port "http" { to = 80 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "nginx:alpine"
        ports = ["http"]
      }

      resources {
        cpu    = 100
        memory = 64
      }

      service {
        name         = "example-server"
        port         = "http"
        address_mode = "host"
        tags         = ["web", "nginx"]
        check {
          type          = "http"
          path          = "/"
          interval      = "15s"
          timeout       = "15s"
          address_mode  = "host"
        }
      }
    }
  }
}