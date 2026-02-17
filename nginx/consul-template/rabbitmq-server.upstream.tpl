# Consul-template: writes upstream from Consul service "rabbitmq" (Nomad job)
# Rendered to nginx/upstreams/rabbitmq-server.conf
upstream rabbitmq_server {
{{ range service "rabbitmq" }}    server {{ or .Address .Node.Address }}:{{ .Port }};
{{ end }}{{ if not (service "rabbitmq") }}    server 127.0.0.1:65535;
{{ end }}
}
