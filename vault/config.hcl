ui = true

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

# Public URL when accessed via nginx (so UI and redirects work)
api_addr = "https://vault.bry.an"

# Enable Prometheus metrics at /v1/sys/metrics?format=prometheus
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname         = true
}
