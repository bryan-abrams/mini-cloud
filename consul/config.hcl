# Consul server with ACLs enabled; Vault will bootstrap and manage tokens.
datacenter = "dc1"
data_dir   = "/consul/data"
ui_config {
  enabled = true
}

acl {
  enabled                  = true
  default_policy            = "deny"
  enable_token_persistence  = true
}
