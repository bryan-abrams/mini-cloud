# Deploying the example nginx app

This walks through running the example nginx job and how a request to **https://example.bry.an** (or whichever domain you use) reaches your app without any hardcoded IPs or ports.

---

## What you’re deploying

The example job (`nomad/examples/nginx.hcl`) runs a small nginx container as a **Nomad service**. Nomad can place it on any healthy client (e.g. your Fedora workers). The container listens on port 80 inside the allocation, but Nomad assigns a **dynamic port** on the host—you don’t know the IP or port until the job is running.

The goal: have **https://example.bry.an** proxy to that service, and have the system figure out *where* it is automatically. This is how scalable and microservice-style setups typically work: you publish a service (the job registers it with Consul) and you let the tooling—service discovery, health checks, dynamic config—figure out where it lives and how to route to it. No hardcoded backends. For services that need many instances running, the same stack can arrange that (e.g. raise the job’s `count`; Consul and nginx pick up the new backends). When load gets heavier, you can also spin up more capacity on demand and let the tools distribute traffic.

Before running the job, you need a TLS certificate for this URL and a hosts entry so the domain resolves to the host. See **setup.md** § 2.1 (certs) and § 2.2 (hostfile).

---

## Deploy the job

With the stack (and workers) up, Nomad ACL bootstrapped, and a token set (see **setup.md** § 2.6 — use `export NOMAD_TOKEN="$(vault read -field=secret_id nomad/creds/job-submitter)"` or your management token for testing):

```bash
nomad job run nomad/examples/nginx.hcl
```

Check that the job is running and the allocation is placed:

```bash
nomad status example
```

You should see an allocation on one or more clients. The service is registered in Consul under the name **example-server** (see the `service { name = "example-server" ... }` block in the job file). That name is the link between "this domain" and "these backends."

---

## How example.bry.an maps to the app (no hardcoded addresses)

Nothing in the nginx config for `example.bry.an` contains a worker IP or port. The chain is:

1. **Nomad** runs the task and assigns a host port (e.g. `28913` on worker `192.168.64.15`). The job's `service` block tells Nomad to **register** that endpoint in **Consul** under the name `example-server`, with the real address and port.

2. **consul-template** (in the Docker stack) watches Consul. It runs a template (`nginx/consul-template/example-server.upstream.tpl`) that asks Consul: "give me all healthy instances of `example-server`." For each instance it gets the node address and port, then **writes** `nginx/upstreams/example-server.conf` with an `upstream example_server { server IP:port; ... }` block.

3. **nginx** is configured to:
   - Serve **https://example.bry.an** (see `nginx/conf.d/example.bry.an.conf`).
   - For that server, `proxy_pass http://example_server` — i.e. "send traffic to the upstream named `example_server`."
   - The upstream definition is **not** in the server block; it's in the file that consul-template writes (`nginx/upstreams/example-server.conf`), which nginx includes. So nginx always uses the current list of backends that Consul knows about.

So: **domain** (example.bry.an) → **upstream name** (example_server) → **file written by consul-template** (from Consul) → **actual IP:port** where Nomad placed the job. No IPs or ports are hardcoded in the nginx server block or the job's network config; discovery is through Consul, and consul-template keeps the upstream file in sync.

After you run the job, give consul-template a few seconds to render and nginx to reload; then open **https://example.bry.an** (with your hostfile pointing that hostname at the host). You should see the default nginx welcome page from the container. Scale the group (change `count` in the job) and consul-template will add more servers to the upstream automatically.

---

## What healthy looks like in Nomad and Consul

If everything is working, you'll see the following.

**Nomad** (https://nomad.bry.an or `nomad status example`): The job **example** is running. The **web** group shows the expected count (e.g. 1) and **Allocations** lists one or more allocations with status **running**. Each allocation is on a client node and shows the assigned port (e.g. **28913**). No allocations should be pending or failed.

**Consul** (https://consul.bry.an): Under **Services**, there is a service named **example-server**. Click it and you'll see one (or more) healthy instance(s). Each instance shows the **Address** (the Nomad client's IP) and **Port** (the dynamic port for that allocation). The health check for each instance should be **passing** (the job defines an HTTP check on `/`). If the service is missing or instances show as failing, the job may not be running yet or the allocation may be unhealthy—check Nomad and the allocation logs.
