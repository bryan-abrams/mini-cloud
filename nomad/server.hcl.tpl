# Nomad server (scheduling); UI and API on :4646
datacenter = "dc1"
region     = "global"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

# Advertise RPC address that clients (e.g. Fedora VM) can reach. Use your Mac's IP
# on the same network as the client; 192.168.64.1 is typical for UTM/shared network.
advertise {
  rpc = "192.168.64.1:4647"
}

server {
  enabled          = true
  bootstrap_expect = 1
}

# Optional: register with Consul for service discovery
consul {
  address = "consul:8500"
  token   = "__CONSUL_TOKEN__"
}
