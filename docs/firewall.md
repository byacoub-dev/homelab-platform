# Firewall Rules

This document describes the network access model and firewall approach used by the Homelab Platform.

Firewall configuration for managed development hosts is maintained through Ansible and UFW.

The objective is not to expose every service port to the entire local network. Instead, access is granted only where a communication path is actually required.

Environment-specific addresses are deliberately kept outside the public repository and supplied through local Ansible configuration.

---

## Design Principles

The firewall model follows several basic rules:

- deny unnecessary inbound access,
- expose service ports only to systems that require them,
- centralize browser-facing access through the reverse proxy,
- allow administrative SSH only where required,
- allow deployment automation through a controlled SSH path,
- keep concrete internal addresses outside the public repository,
- manage firewall state through Ansible instead of manual host changes.

The intended model is:

```text
                 Internal Clients
                        │
                        ▼
                Reverse Proxy
                        │
              explicitly allowed
                 service ports
                        │
                        ▼
                Development Host


                 Operations Host
                        │
                       SSH
                        │
                        ▼
                Development Host


                  CD Runner
                        │
                       SSH
                        │
                        ▼
                Development Host
```

Direct client access to backend service ports is avoided where the reverse proxy provides the intended user-facing entry point.

---

## Trust Zones

The current architecture can be divided into several functional zones.

### Client Network

Normal clients consume applications through internal DNS and the central reverse proxy.

They generally do not require direct access to application backend ports.

### Reverse Proxy

The central reverse proxy is allowed to reach selected HTTP backend ports on managed hosts.

It acts as the primary application entry point.

### Operations

The operations environment requires SSH access to managed systems for manual Ansible execution, troubleshooting and administration.

### Deployment Automation

The dedicated Self-hosted GitHub Actions Runner requires SSH access to the development target for automated Ansible execution.

### Development Host

The development host exposes only the ports required by these defined communication paths.

---

## Development Host Access

The following application connections are currently relevant for services running on development hosts:

| Source | Target | Port | Protocol | Purpose |
|---|---|---:|---|---|
| Reverse proxy | Development host | `3000` | TCP | What's Up Docker |
| Reverse proxy | Development host | `3001` | TCP | Grafana |
| Reverse proxy | Development host | `9090` | TCP | Prometheus |
| Authorized administration source | Development host | `22` | TCP | SSH administration |
| Authorized CD runner | Development host | `22` | TCP | Ansible deployment |

The table describes logical access requirements.

Concrete source and destination addresses are environment-specific and therefore not stored in this document.

---

## Reverse Proxy Access

Browser-facing services should normally be reached through the central reverse proxy.

The intended path is:

```text
Client
   │
   │ HTTPS
   ▼
Reverse Proxy
   │
   │ explicitly permitted backend connection
   ▼
Development Host
   │
   ▼
Docker Service
```

This means that a service such as Grafana does not need to expose its backend port to every client in the local network.

Instead:

```text
Client ─────────────X────────────► Grafana backend port

Client
   │
   ▼
Reverse Proxy
   │
   └─────────────────────────────► Grafana backend port
```

The exact policy depends on the requirements of each service.

---

## SSH Access

SSH is required for two separate purposes.

### Manual Administration

The operations environment uses SSH for:

- manual Ansible execution,
- troubleshooting,
- system administration.

```text
Operations Host
      │
      │ SSH / TCP 22
      ▼
Development Host
```

### Automated Deployment

The dedicated CD runner also requires SSH access to the development target.

```text
GitHub
   │
   ▼
CD Runner
   │
   │ SSH / TCP 22
   ▼
Development Host
```

The runner uses dedicated deployment credentials and a dedicated automation account rather than reusing the normal administrative identity.

Although both paths use SSH, they represent different operational responsibilities and should therefore remain conceptually separated.

---

## Node Exporter

Node Exporter exposes host metrics on TCP port:

```text
9100
```

It does not need to be exposed through the reverse proxy when Prometheus can reach it directly.

The preferred path is:

```text
Prometheus
    │
    │ TCP 9100
    ▼
Node Exporter
```

rather than:

```text
Prometheus
    │
    ▼
Reverse Proxy
    │
    ▼
Node Exporter
```

This keeps the metrics collection path independent from the browser-facing reverse proxy.

The exact firewall rule for Node Exporter should therefore permit only the monitoring source that actually requires access.

---

## Monitoring Traffic

The intended monitoring communication model is:

```text
                 Monitoring Host
                       │
              ┌────────┴────────┐
              │                 │
              ▼                 ▼
        Node Exporter      Other Metrics
          TCP 9100           Endpoints
              │
              ▼
           Prometheus
              │
              ▼
            Grafana
```

Where Prometheus and Grafana run on the same Docker host or network, their internal communication does not necessarily require an additional host firewall rule.

Firewall rules should reflect actual network boundaries rather than automatically exposing every application port.

---

## Ansible Firewall Management

Firewall rules are managed through the Ansible role:

```text
automation/ansible/roles/firewall/
```

The corresponding playbook is:

```text
automation/ansible/playbooks/configure-firewall.yml
```

Environment-specific values are supplied through local configuration such as:

```text
automation/ansible/group_vars/development.yml
```

A public template is provided through:

```text
automation/ansible/group_vars/development.yml.example
```

For example:

```yaml
---
reverse_proxy_ip: "192.168.1.10"
```

The address above is only an example.

The actual address used by the homelab is maintained locally and excluded from Git.

---

## Applying Firewall Configuration

From the Ansible control environment, the firewall configuration can be applied with:

```bash
ansible-playbook playbooks/configure-firewall.yml -K
```

The `-K` option requests the privilege escalation password for tasks using:

```yaml
become: true
```

The firewall role ensures that the required UFW rules exist and enables UFW.

The automation is intended to be idempotent.

Repeated execution should therefore converge toward the same desired firewall state instead of creating duplicate rules.

---

## Verification

After applying firewall configuration, the resulting rules can be inspected on the target host with:

```bash
sudo ufw status numbered
```

A firewall change should not be considered complete only because the Ansible playbook succeeds.

The required communication paths should also be tested.

For example:

```text
Reverse Proxy
      │
      └── Can required backend be reached?

Operations Host
      │
      └── Does SSH still work?

CD Runner
      │
      └── Does Ansible connectivity still work?

Unauthorized Client
      │
      └── Is unnecessary direct backend access blocked?
```

This verifies both required connectivity and intended restrictions.

---

## Firewall and CI/CD

The introduction of the Self-hosted CD runner adds a specific network requirement:

```text
runner01
   │
   │ SSH
   ▼
Development Host
```

The runner does not require direct access to every application port merely because it performs deployments.

Ansible deployment is performed over SSH.

The services themselves are subsequently reached through their intended application or monitoring paths.

Conceptually:

```text
                     CD Runner
                         │
                        SSH
                         │
                         ▼
                  Development Host
                         │
                     Docker Engine
                         │
                         ▼
                      Service


                     Reverse Proxy
                         │
                  application port
                         │
                         ▼
                      Service
```

Deployment access and application access are therefore treated as separate firewall concerns.

---

## Public Repository Boundary

Real network addresses are not stored in the public repository.

The repository contains:

```text
Firewall role
Example variables
Documentation
```

The local environment contains:

```text
Actual source addresses
Actual target addresses
Private inventory
Credentials
```

This produces the following separation:

```text
Public Git Repository
        │
        ├── desired firewall logic
        └── example configuration

Local Environment
        │
        ├── actual network values
        └── deployment credentials
```

The firewall logic remains reproducible without publishing the concrete private network topology.

---

## Rule Management

Required firewall changes should be introduced through the Ansible role rather than by permanently modifying UFW manually on individual managed hosts.

The intended workflow is:

```text
Required Network Change
        │
        ▼
Modify Ansible Role / Variables
        │
        ▼
Validate
        │
        ▼
Pull Request
        │
        ▼
CI
        │
        ▼
Merge
        │
        ▼
Apply Desired Firewall State
        │
        ▼
Verify Connectivity
```

Temporary manual rules may be useful during troubleshooting, but the final desired state should be represented by automation.

This prevents configuration drift between the documented infrastructure and the actual host configuration.

---

## Current Security Model

The current network model can be summarized as:

```text
                         Clients
                            │
                            ▼
                      Reverse Proxy
                            │
                   selected TCP ports
                            │
                            ▼
                     Development Host
                            ▲
                            │
               ┌────────────┴────────────┐
               │                         │
             SSH                       SSH
               │                         │
        Operations Host              CD Runner
```

Monitoring adds a separate machine-to-machine path:

```text
Prometheus
    │
    │ TCP 9100
    ▼
Node Exporter
```

Only explicitly required communication paths should be permitted.

---

## Current and Planned Scope

Currently relevant firewall-controlled access includes:

- SSH for manual administration,
- SSH for automated Ansible deployment,
- WUD access through the reverse proxy,
- Grafana access through the reverse proxy,
- Prometheus access through the reverse proxy,
- Node Exporter access from the monitoring source.

As additional services are deployed, their firewall requirements should be evaluated individually.

A new service should not automatically result in a generally open LAN port.

The required questions are:

1. Who needs to access the service?
2. Does access need to pass through the reverse proxy?
3. Is the connection user-facing or machine-to-machine?
4. Can the source be restricted?
5. Does the service need a host port at all?

Only after these questions are answered should the corresponding rule become part of the desired firewall configuration.

---

## Summary

The firewall model follows a simple principle:

> Allow the communication paths the platform requires, not every port a service happens to expose.

The current architecture separates:

- user-facing access through the reverse proxy,
- manual administration through SSH,
- automated deployment through SSH,
- monitoring traffic through dedicated metrics endpoints.

UFW provides host-level enforcement while Ansible keeps the desired rule set reproducible.

Concrete network addresses remain local and outside the public repository.

As the platform grows, additional rules should continue to be introduced through version-controlled automation and verified against the real communication requirements of each service.
