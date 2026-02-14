# Nomad server (scheduling); UI and API on :4646
datacenter = "dc1"
region     = "global"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

# Advertise addresses for Consul health checks (same Docker network) and for
# RPC so clients (e.g. Fedora VM) can reach the server. Use your Mac's IP on the
# same network as the client; 192.168.64.1 is typical for UTM/shared network.
advertise {
  http = "nomad-server:4646"
  rpc  = "192.168.64.1:4647"
  serf = "nomad-server:4648"
}

server {
  enabled          = true
  bootstrap_expect = 1
}

# Optional: register with Consul for service discovery
consul {
  address              = "consul:8500"
  token                = "__CONSUL_TOKEN__"
  checks_use_advertise  = true
}

# Enable Prometheus metrics at /v1/metrics?format=prometheus
telemetry {
  collection_interval        = "1s"
  disable_hostname           = true
  prometheus_metrics         = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}
