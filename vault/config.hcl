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
