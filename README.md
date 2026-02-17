# Mini-cloud

<p align="center">
  <img src="docs/images/myowncloud.png" alt="I'll make my own cloud" width="400" />
</p>

A fully isolated “cloud” environment that runs on your own machine. It gives you the same kinds of building blocks you see on platforms like AWS, Azure, or Google Cloud—containers, orchestration, service discovery, secrets, and CI/CD—so you can learn how they work without touching real cloud accounts or paying for hosted services.

This stack was built on a macOS host, but any macOS or Linux host with a container engine that can run virtual machines (e.g. for worker nodes) should be able to run the same setup.

## Documentation

| Document | Description |
|----------|--------------|
| [Architecture](docs/architecture.md) | Topology, service roles, Consul → nginx flow, and diagrams. |
| [Setup](docs/setup.md) | Prerequisites, certs, hostfile, and bootstrapping the stack (Vault unseal, Nomad ACL bootstrap, tokens). |
| [Usage](docs/usage.md) | Portals, URLs, and day-to-day use (including Prometheus at `metrics.bry.an` and Grafana at `dash.bry.an`). |
| [Cheatsheet](docs/cheatsheet.md) | Vault, Nomad, and Consul CLI and HTTP API quick reference. |
| [Deploy example](docs/deploy-example.md) | Deploy the example nginx job and see how it maps to a domain. |
| [Fedora UTM worker](docs/fedora-utm-worker.md) | Run a Nomad worker on a Fedora VM in UTM. |

---

## Why this exists

In real clouds you typically get:

- **Containers** (e.g. AWS ECS, EKS, or Elastic Container Service) that run your apps.
- **Load balancers / API gateways** that receive HTTPS traffic and send it to the right service.
- **Service discovery** so services find each other by name instead of hard-coded IPs.
- **Secrets management** (e.g. AWS Secrets Manager, HashiCorp Vault) for API keys and certs.
- **CI/CD** (e.g. GitHub Actions, AWS CodePipeline) to build, test, and deploy from code.
- **Databases** and admin UIs (e.g. RDS + a console) for development and debugging.

Mini-cloud reproduces that picture on your laptop: you get a small “elastic container” style setup with orchestration (something that decides *where* and *how* to run your apps), microservices (several small services talking over the network), and a single edge (nginx) that terminates HTTPS and routes to the right backend. No cloud account required. Every point in that picture can be inspected and debugged—you have access to the full path from developing an application to running it in this cloud environment.

---

## How it mimics “real” cloud and microservices

| Real-world idea | What it usually means | What mini-cloud uses |
|-----------------|------------------------|------------------------|
| **Containers / “elastic containers”** | Your app runs in a container; the platform can start more or fewer copies. | **Nomad** schedules and runs containerized tasks (like ECS or Kubernetes). Tasks run on **worker** machines (VMs on your LAN), not inside the main Docker Compose stack. |
| **Orchestration** | A central system decides *which* machine runs *which* workload and keeps it running. | **Nomad** is the orchestrator: it places jobs on workers, restarts failed tasks, and registers services so others can find them. |
| **Service discovery** | Services find each other by name (e.g. `payments-api`) instead of IP:port. Instances can come and go; discovery keeps the list up to date. | **Consul** is the service registry. Nomad registers each task with Consul; **consul-template** turns that into nginx upstream config so the edge proxy always points at healthy instances. |
| **Edge / API gateway** | One place that handles HTTPS and routes requests to the right backend (often with a load balancer). | **Nginx** terminates HTTPS and reverse-proxies by hostname to fixed backends (Gitea, Vault, etc.) and to **Consul-discovered** backends (e.g. apps running on Nomad workers). |
| **Secrets** | Central place to store and hand out API keys, certs, tokens. | **HashiCorp Vault** holds secrets and can issue tokens (e.g. for Consul ACLs). |
| **Source control + CI/CD** | Code in Git, pipelines that build and deploy. | **Gitea** (internal Git + **package registry**) and **Concourse CI** (pipelines as YAML, visualized in a UI). Gitea’s registry lets you mimic having **package management as part of your services**—publish and consume internal packages (e.g. npm, NuGet, apt, brew) so builds and deployments pull from your own repo instead of the public internet. |
| **Database + admin UI** | Managed DB and a way to browse it. | **PostgreSQL** plus **PgAdmin** for browsing and debugging. |
| **Monitoring / metrics** | Central place to collect and query metrics (CPU, request rates, health). | **Prometheus** scrapes metrics from Consul, Nomad, Vault, Gitea, and Concourse. **Grafana** at `https://dash.bry.an` uses Prometheus as a data source so you can build dashboards with multiple panels, auto-refresh, and smaller graphs. Raw PromQL and targets remain at `https://metrics.bry.an`. |

So in practice: you define a small app (or use the example) as a Nomad job. Nomad runs it in a container on a worker. The job registers a service in Consul. Consul-template updates nginx’s config so that a hostname (e.g. `example.bry.an`) proxies to that service. That’s the same *pattern* as “elastic containers” plus a load balancer and service discovery in a big cloud—just scaled down to your machine and a couple of VMs.

---

## Components

| Component | URL | Purpose |
|-----------|-----|---------|
| **Nginx** | [nginx.org](https://nginx.org/) | The front door: HTTPS only, routes by domain (e.g. `git.bry.an`, `example.bry.an`) to the right backend. For Nomad-run apps, it uses upstreams generated from Consul. |
| **HashiCorp Consul** | [consul.io](https://www.consul.io/) | Service discovery and health: “Where is `example-server` right now?” Consul holds the list; nginx (via consul-template) uses it to send traffic to the right VM:port. |
| **HashiCorp Nomad** | [nomadproject.io](https://www.nomadproject.io/) | Orchestrator: runs your containerized workloads on worker nodes, restarts them if they fail, and registers them in Consul so they can be discovered. |
| **HashiCorp Vault** | [vaultproject.io](https://www.vaultproject.io/) | Secret store: API keys, certs, tokens. Integrated with Consul (e.g. for ACL tokens) so other parts of the stack can get credentials automatically. |
| **Gitea** | [gitea.io](https://gitea.io/) | Internal Git (like GitHub) plus a **package registry**. Meant to give you internal package management as part of your services: publish and consume your own packages (npm, NuGet, apt, brew, etc.) so CI and deployments use your private registry instead of public package sources—same idea as enterprise internal registries, but inside this mini-cloud. |
| **Concourse CI** | [concourse-ci.org](https://concourse-ci.org/) | CI/CD with a UI: workflows are YAML, version-controlled. Good for “push to Git → build → deploy” style pipelines. |
| **PostgreSQL** | [postgresql.org](https://www.postgresql.org/) | Shared SQL database used by Gitea, Concourse, and PgAdmin. |
| **PgAdmin** | [pgadmin.org](https://www.pgadmin.org/) | Web UI to browse and query the PostgreSQL database for debugging. |
| **Prometheus** | [prometheus.io](https://prometheus.io/) | Monitoring and metrics: scrapes Prometheus-format metrics from Consul, Nomad, Vault, Gitea, and Concourse so you can query and graph them. Exposed via nginx at `metrics.bry.an`. |
| **Grafana** | [grafana.com](https://grafana.com/) | Dashboard UI for metrics: connects to Prometheus as a data source so you can build multi-panel dashboards with auto-refresh and resizable graphs. Exposed via nginx at `dash.bry.an`. |

For more detail on how these pieces connect (including diagrams), see [Architecture](docs/architecture.md).

---

## Design: access and network

By design, the stack is intended to be accessed only by the host—the machine running the Docker Compose stack. UIs and APIs (Gitea, Consul, Nomad, etc.) are meant for you on that machine, not for arbitrary external users.

Workers don’t have to run on the host. They can be external (e.g. other VMs or machines on your LAN). When workers are external, you must expose traffic between the Compose network and those workers: the Nomad server and nginx need to reach worker IPs for RPC and for proxying to tasks, and workers need to reach Consul (and optionally the Nomad server) over the network. That usually means routing and possibly firewall rules so the host (and thus the Compose containers) can talk to the worker subnet. In a normal scenario—e.g. host and workers all on the same LAN or a network where they already have access to each other—this isn’t an issue; the “expose traffic” step is only when workers sit on a different segment or you’re wiring things across networks manually.

Exposing that traffic can make the stack reachable by everyone on a particular network (e.g. your LAN). That trade-off should be considered if you start workers on another computer or on a VM that is not in a shared network mode (e.g. bridged): to get connectivity you may have to bind ports or routes to the LAN, which then exposes the host’s services to that network. If the stack is meant for host-only use, keep workers on the host’s network in a way that doesn’t require opening the stack to the rest of the network, or restrict access with a firewall.
