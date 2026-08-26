# Architecture

## Host roles

### Raspberry Pi
Always-on host for stable homelab services.

Current role:
- DNS with AdGuard Home
- Vaultwarden
- Paperless-ngx
- ntfy
- Caddy reverse proxy
- container update notifications

### core01
On-demand development and DevOps lab.

Current role:
- Docker and Docker Compose
- development environment
- testing new services
- future CI/CD, automation and Kubernetes workloads

## Design principle

Stable 24/7 services remain on the Raspberry Pi.
Experimental and resource-intensive workloads run on core01.
