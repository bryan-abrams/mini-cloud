# Consul server with ACLs enabled; Vault will bootstrap and manage tokens.
# Rendered at startup: __CONSUL_AGENT_TOKEN__ replaced by CONSUL_HTTP_TOKEN from host.
datacenter = "dc1"
data_dir   = "/consul/data"
ui_config {
  enabled = true
}

acl {
  enabled                  = true
  default_policy            = "deny"
  enable_token_persistence  = true
  tokens {
    agent = "__CONSUL_AGENT_TOKEN__"
  }
}
