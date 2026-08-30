# Architecture

This document describes the current architecture of the homelab, the responsibilities of its hosts and the basic communication between services.

The environment is intentionally split between stable always-on infrastructure and a more flexible workload and development host.

## Host Roles

### Raspberry Pi

The Raspberry Pi is the always-on infrastructure host.

It runs central services that should remain available independently of the development environment:

- **AdGuard Home** – local DNS resolution
- **Caddy** – central reverse proxy and internal TLS
- **Vaultwarden** – password management
- **Paperless-ngx** – document management
- **ntfy** – notifications

### core01

`core01` is an Ubuntu Server system used for additional workloads, monitoring and infrastructure development.

Current responsibilities include:

- Docker and Docker Compose
- **Prometheus** – metrics collection
- **Grafana** – dashboards and visualization
- **Node Exporter** – host-level metrics
- **WUD** – container update monitoring
- testing and integrating new infrastructure services

Unlike the Raspberry Pi, `core01` does not need to provide the central 24/7 services and can therefore be used more flexibly for development and experimentation.

## Host Architecture

```text
                         Homelab
                            │
           ┌────────────────┴────────────────┐
           │                                 │
     Raspberry Pi                         core01
      (always-on)                     (Ubuntu Server)
           │                                 │
     ┌─────┼──────────────┐          ┌───────┼─────────┐
     │     │              │          │       │         │
 AdGuard  Caddy      Applications  Prometheus Grafana  WUD
   DNS   Reverse Proxy                  │
                 │                      └── Node Exporter
                 │
        ┌────────┼────────┐
        │        │        │
   Vaultwarden Paperless ntfy
```

The Raspberry Pi provides the central network-facing services, while `core01` hosts monitoring and development workloads.

## DNS and Service Access

AdGuard Home provides local DNS resolution for the homelab.

Services use internal `home.arpa` hostnames instead of requiring users to access individual IP addresses and ports directly.

DNS resolution and the actual service connection are separate steps.

```text
DNS resolution:

Client ──────> AdGuard Home
       query     │
                 │
Client <─────────┘
       address
```

After the hostname has been resolved, the client connects to Caddy using HTTPS.

```text
Web request:

Client
  │
  │ HTTPS
  ▼
Caddy
  │
  │ reverse_proxy
  ▼
Target service
  │
  ├── Raspberry Pi service
  │
  └── core01 service
```

Caddy therefore acts as the central entry point for web services and forwards requests to the appropriate backend.

Services running on the same Docker host communicate through Docker networks where appropriate. Services located on another host are reached through the local network.

## Monitoring

The monitoring stack currently consists of Prometheus, Grafana and Node Exporter.

```text
Node Exporter
     │
     │ metrics
     ▼
 Prometheus
     │
     │ data source
     ▼
   Grafana
```

Prometheus collects metrics from configured targets.

Node Exporter exposes host-level metrics from `core01`, while Grafana uses Prometheus as its data source for dashboards and visualization.

Prometheus target definitions are separated from the reusable repository configuration. The repository contains `nodes.yml.example`, while the actual `nodes.yml` remains local.

This keeps host-specific addresses outside the public repository while still documenting how additional monitoring targets can be configured.

## Configuration and Persistence

The repository contains configuration that is useful for understanding and reproducing the environment.

Sensitive information, host-specific configuration and persistent application data remain outside version control.

Examples of local files include:

- `.env` – environment-specific values and credentials
- `Caddyfile` – actual local reverse proxy configuration
- `nodes.yml` – actual Prometheus targets
- persistent Docker application data

Where useful, corresponding example files are stored in the repository:

```text
.env.example
Caddyfile.example
nodes.yml.example
```

This keeps the repository reusable without exposing credentials or unnecessary details of the local environment.

## Design Principles

The architecture follows a few practical principles:

- Stable 24/7 services remain on the Raspberry Pi.
- Monitoring and development workloads run on `core01`.
- Services are containerized with Docker where practical.
- Configuration is version-controlled while secrets and runtime data remain local.
- Docker networks are used for communication between containers on the same host where appropriate.
- Infrastructure should become increasingly reproducible instead of relying on undocumented manual configuration.
- New technologies are introduced when they solve an actual problem rather than only to increase the size of the technology stack.

The architecture will continue to evolve as monitoring, automation and deployment workflows are expanded.