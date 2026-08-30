# Homelab Platform

This repository documents the configuration of my personal homelab and serves as a practical environment for working with Linux, Docker, networking, monitoring and infrastructure automation.

The goal is not to introduce as many technologies as possible, but to build an environment that is useful, understandable and increasingly reproducible. The homelab is actively used and extended step by step.

## Architecture

The environment is currently split across two hosts with different responsibilities:

- **Raspberry Pi** – runs central services that should remain available 24/7, including DNS, reverse proxy and core applications.
- **core01** – Ubuntu Server used for additional workloads, monitoring and further infrastructure development.

This keeps essential services on a low-power always-on system while `core01` can be used more flexibly for development and experimentation.

A more detailed description is available in [`docs/architecture.md`](docs/architecture.md).

## Current Stack

| Area | Technologies |
| --- | --- |
| Containers | Docker, Docker Compose |
| Systems | Ubuntu Server, Raspberry Pi OS |
| DNS | AdGuard Home |
| Reverse Proxy / TLS | Caddy |
| Monitoring | Prometheus, Grafana, Node Exporter |
| Notifications | ntfy |
| Applications | Vaultwarden, Paperless-ngx, WUD |
| Version Control | Git, GitHub |

## Networking & Monitoring

AdGuard Home provides local DNS resolution using internal `home.arpa` hostnames.

Caddy acts as the central reverse proxy and provides HTTPS using its internal CA. Services on the same Docker host communicate through Docker networks where possible, while services running on another host are reached through the local network.

The monitoring stack currently consists of **Prometheus, Grafana and Node Exporter**. Prometheus collects metrics from configured targets, Node Exporter provides host-level metrics and Grafana is used for visualization and dashboards.

## Repository Structure

The repository follows a service-centric structure:

```text
.
├── docs/
│   └── architecture.md
├── services/
│   ├── adguard/
│   ├── caddy/
│   ├── grafana/
│   ├── node-exporter/
│   ├── ntfy/
│   ├── paperless/
│   ├── prometheus/
│   ├── vaultwarden/
│   └── wud/
├── .gitignore
└── README.md
```

Configuration is kept close to the corresponding service.

Sensitive and host-specific configuration is not stored in the repository. Instead, example files such as `.env.example`, `Caddyfile.example` and `nodes.yml.example` document the required structure while credentials, runtime data and local configuration remain outside Git.

## Principles

- Keep configuration understandable and maintainable.
- Prefer reproducible deployments over manual configuration.
- Keep secrets and persistent runtime data outside version control.
- Separate always-on infrastructure from development workloads.
- Document decisions that are relevant for operating or rebuilding the environment.
- Introduce new technologies when they provide practical value instead of adding complexity only for demonstration purposes.

## Current Focus

The homelab is actively being developed. The current focus is on improving monitoring and observability and making infrastructure configuration increasingly reproducible.

Planned next steps include:

- expanding Prometheus monitoring and Grafana dashboards
- adding alerting for relevant infrastructure events
- introducing CI/CD checks for repository changes
- using Ansible for repeatable configuration and deployments
- gradually exploring Infrastructure as Code
- evaluating Kubernetes when there is a practical use case for orchestration

The repository will continue to evolve together with the actual homelab environment.