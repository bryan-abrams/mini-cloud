# Change bind_addr to the IP address assigned by DHCP when you created the machine
datacenter = "dc1"
region     = "global"
data_dir   = "/opt/nomad/data"
bind_addr  = "192.168.64.n"

# So Consul can reach this client's HTTP API for the "Nomad Client HTTP Check"
advertise {
  http = "192.168.64.n:4646"
  rpc  = "192.168.64.n:4647"
}

# The server needs to be the VM's shared network gateway so that
# it calls back to your host
client {
  enabled = true
  servers = ["192.168.64.1:4647"]
}

# See setup.md for generating tokens
consul {
  address = "consul.bry.an:443"
  ssl     = true
  token   = ""
}

# Depending on Host OS, you need to change this
# to the socket the container engine listens on
plugin "docker" {
  config {
    endpoint          = "unix:///run/podman/podman.sock"
    allow_privileged  = false
  }
}