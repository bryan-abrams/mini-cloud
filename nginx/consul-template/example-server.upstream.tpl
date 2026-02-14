# Consul-template: writes upstream from Consul service "example-server" (Nomad job)
# Rendered to nginx/upstreams/example-server.conf
upstream example_server {
{{ range service "example-server" }}    server {{ or .Address .Node.Address }}:{{ .Port }};
{{ end }}{{ if not (service "example-server") }}    server 127.0.0.1:65535;
{{ end }}
}
