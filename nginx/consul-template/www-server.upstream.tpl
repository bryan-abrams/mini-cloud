# Consul-template: writes upstream from Consul service "www-server" (Nomad job)
# Rendered to nginx/upstreams/www-server.conf
upstream www_server {
{{ range service "www-server" }}    server {{ or .Address .Node.Address }}:{{ .Port }};
{{ end }}{{ if not (service "www-server") }}    server 127.0.0.1:65535;
{{ end }}
}
