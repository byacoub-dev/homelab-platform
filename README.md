# Homelab Platform

A practical DevOps homelab for learning and implementing containerized infrastructure, configuration management, CI/CD, monitoring, networking, backup and recovery.

The project is not intended to be a collection of self-hosted applications. Its primary purpose is to build a small but realistic platform in which infrastructure changes are versioned, validated, automated and documented.

The environment is built around Docker Compose, Ansible, GitHub Actions, Proxmox, Prometheus and Grafana. Stable infrastructure services are separated from development and automation workloads, while the public repository contains only reusable configuration and generic examples.

> **Documented state: 09 October 2026.** DevOps and platform engineering remain the main focus: reusable Docker Compose definitions, Ansible automation, reviewed Git changes, CI validation and recovery. Monitoring is now operational on `dev01`, including host metrics, eight internal HTTPS checks and Grafana Service Health V3. The isolated CD path is verified for connectivity only; automated service deployment through that workflow is not yet confirmed.

This overview is based on the user's `HOMELAB.md` dated 09 October 2026 and the current repository configuration. Runtime observations describe that documented state, not a live infrastructure audit.

---

## Goals

The project is designed around a few core principles:

- infrastructure and service configuration should be reproducible,
- changes should be versioned and reviewed before deployment,
- CI and CD should have clearly separated responsibilities,
- development and infrastructure workloads should be isolated where useful,
- persistent application data should remain separate from Git,
- secrets and private infrastructure details must not be committed,
- monitoring should provide operational value rather than only dashboards,
- backups are only considered useful when restoration has been tested,
- new tools should solve an actual problem or provide a concrete learning benefit.

The long-term goal is to use the homelab as a realistic environment for developing practical DevOps, platform engineering and infrastructure automation skills.

---

## Architecture

The current environment combines a small Proxmox virtualization platform with a dedicated Raspberry Pi for stable infrastructure services.

```text
                           GitHub
                              │
                ┌─────────────┴─────────────┐
                │                           │
          Pull Request                 Push to main
                │                           │
                ▼                           ▼
       GitHub-hosted Runner        Self-hosted Runner
                │                     runner01
                │                           │
                ▼                           │
         CI Validation                     │
     ┌────────────────────┐                 │
     │ YAML validation    │                 │
     │ Ansible syntax     │                 │
     │ Compose validation │                 │
     └────────────────────┘                 │
                                            │
                                      SSH / Ansible
                                            │
                                            ▼
                                          dev01
                                    Development Target
                                            │
                                            ▼
                                  Ansible ping verified
                                  (no CD deployment yet)


                  Internal Homelab Network
                           │
              ┌────────────┴────────────┐
              │                         │
          Proxmox Host             Raspberry Pi
              │                         │
       ┌──────┼──────┐          Stable 24/7 Services
       │      │      │                  │
     dev01  ops01  runner01       ┌─────┼─────────────┐
                                  │     │             │
                               AdGuard Caddy     Applications
```

The physical Proxmox host remains intentionally lightweight. Development, operations and CI/CD workloads are placed in separate virtual machines.

The Raspberry Pi continues to host stable 24/7 infrastructure services such as DNS, reverse proxy and selected applications.

| Host | Current responsibility |
|---|---|
| `core01` | Proxmox hypervisor; application workloads run in VMs |
| `dev01` | Docker development/deployment target, WUD and monitoring stack |
| `ops01` | Manual Ansible control node and operations |
| `runner01` | Isolated self-hosted runner; CD connectivity verification |
| Raspberry Pi | AdGuard, Caddy, Homepage, Paperless-ngx, Vaultwarden, ntfy and Node Exporter |

Immich is outside the current intended operating state. Kubernetes/k3s has not been started.

---

## CI/CD Architecture

CI and CD are deliberately separated.

### Continuous Integration

Every pull request targeting `main` is validated using a GitHub-hosted runner.

The CI workflow currently performs:

- YAML validation with `yamllint`,
- Ansible playbook syntax checks,
- Docker Compose configuration validation,
- installation of the Ansible collections defined by the repository.

This allows configuration errors to be detected before changes are merged.

```text
Feature Branch
      │
      ▼
Pull Request
      │
      ▼
GitHub-hosted Runner
      │
      ├── yamllint
      ├── Ansible syntax-check
      └── docker compose config
      │
      ▼
Review / Merge
```

The CI workflow does not require access to the private homelab network.

---

### Continuous Deployment

The CD connectivity job uses a dedicated self-hosted GitHub Actions runner named `runner01`.

The runner is hosted in its own virtual machine and is deliberately separated from the normal Ansible control node.

The CD workflow currently performs:

1. checkout of the repository,
2. installation of the required Ansible collections,
3. loading of the runner-local Ansible inventory,
4. SSH connection to the development target,
5. Ansible connectivity verification.

```text
Merge to main
      │
      ▼
GitHub Actions
      │
      ▼
runner01
Self-hosted Runner
      │
      ├── Checkout repository
      ├── Install Ansible collections
      └── Run Ansible
              │
              ▼
            dev01
```

The complete transport path has been successfully tested.

The current [CD workflow](.github/workflows/cd.yml) installs collections and runs `ansible all -m ping` against the runner-local inventory. It does not invoke a deployment playbook. Node Exporter already runs on `dev01`, but its deployment through CD is not confirmed. A future controlled deployment must be added explicitly and verified after execution.

Production services on the Raspberry Pi are deliberately excluded from automatic deployment at this stage.

---

## Trust Boundaries

The repository is public, which makes the handling of self-hosted GitHub Actions runners particularly important.

Unreviewed pull-request code must never execute directly inside the private infrastructure.

The architecture therefore separates untrusted CI execution from trusted CD execution:

```text
                    PUBLIC / UNTRUSTED

                         GitHub
                            │
                     Pull Requests
                            │
                            ▼
                  GitHub-hosted Runner
                            │
                      CI Validation


────────────────────── TRUST BOUNDARY ──────────────────────


                      Push to main
                            │
                            ▼
                        runner01
                  Self-hosted CD Runner
                            │
                       SSH / Ansible
                            │
                            ▼
                          dev01
```

The self-hosted runner is intentionally not used for `pull_request` events.

The CD workflow is triggered only by:

- pushes to `main`,
- explicit manual execution through `workflow_dispatch`.

This behavior has been verified in practice: the pull request introducing the CD workflow executed only the GitHub-hosted CI. The self-hosted runner was contacted only after the pull request had been merged into `main`.

---

## Ansible Automation

Ansible is used for provisioning and service deployment.

The automation is stored separately from the service definitions:

```text
automation/ansible/
├── ansible.cfg
├── collections/
│   └── requirements.yml
├── inventory/
│   ├── hosts.yml.example
│   └── group_vars/
│       └── development.yml.example
├── playbooks/
│   ├── bootstrap.yml
│   ├── configure-firewall.yml
│   ├── deploy-blackbox-exporter.yml
│   ├── deploy-grafana.yml
│   ├── deploy-node-exporter.yml
│   ├── deploy-prometheus.yml
│   ├── deploy-wud.yml
│   └── system-info.yml
└── roles/
    ├── blackbox_exporter/
    ├── common/
    ├── docker/
    ├── firewall/
    ├── grafana/
    ├── node_exporter/
    ├── prometheus/
    └── wud/
```

Reusable roles are preferred over host-specific automation.

The current roles cover areas including:

- base system configuration,
- Docker installation,
- firewall configuration,
- Node Exporter,
- Prometheus,
- Blackbox Exporter,
- Grafana,
- WUD.

Ansible has already been used to provision the development environment and deploy WUD reproducibly.

Idempotency is an explicit goal. Re-running a deployment should not cause unnecessary changes when the desired state is already present.

---

## Inventory and Environment Separation

Real infrastructure values are not stored in the public repository.

For example:

```text
inventory/
├── hosts.yml          # local, ignored by Git
└── hosts.yml.example  # public example
```

The same principle applies to environment-specific variables.

```text
inventory/group_vars/
├── development.yml          # local, ignored
└── development.yml.example  # public example
```

This allows the repository to document the expected structure without coupling it to the actual homelab network.

Hostnames, internal addresses and environment-specific values remain local.

---

## Service Model

Services are organized independently from the hosts on which they run.

```text
services/
├── adguard/
├── blackbox-exporter/
├── caddy/
├── grafana/
├── homepage/
├── node-exporter/
├── ntfy/
├── paperless/
├── prometheus/
├── vaultwarden/
└── wud/
```

A service directory typically contains:

```text
service/
├── compose.yml
├── .env.example
└── additional configuration
```

The repository does not prescribe that a particular service must run on a particular host.

This allows the same definitions to be reused when the infrastructure changes.

Host-specific deployment decisions are deliberately kept outside the reusable service definitions.

---

## Persistent Data

Git contains configuration, not application state.

Persistent data is stored outside the repository using a consistent host-side structure:

```text
/srv/appdata/<service>
```

Deployment directories use:

```text
/srv/stacks/<service>
```

This separation makes it possible to:

- recreate containers without losing application data,
- version configuration independently from runtime state,
- back up important data without backing up Git working trees,
- migrate services between hosts more predictably.

Database files, uploads, application state and other runtime data are never committed to the repository.

---

## Networking and Reverse Proxy

AdGuard provides internal DNS resolution.

Caddy acts as the central reverse proxy for HTTP/HTTPS services.

The general access path is:

```text
Client
  │
  ▼
AdGuard DNS
  │
  ▼
Caddy
  │
  ├── Local container
  │
  └── Service on another internal host
```

Internal service names use the `home.arpa` namespace.

Caddy uses its internal certificate authority for local TLS.

This allows services to be accessed using readable internal names instead of exposing host ports directly to users.

---

## Monitoring

Monitoring supports operating and troubleshooting the platform. The migration to `dev01` is complete in the documented state.

```text
Node Exporter on dev01 and Raspberry Pi ──► Prometheus ──► Grafana
                                               ▲
                                               │ probe metrics
                                        Blackbox Exporter
                                               │
                                  internal DNS → Caddy → HTTPS services
```

### Host and service checks

Node Exporter provides host metrics for `dev01` and the Raspberry Pi. Prometheus collects them through file-based discovery; the documented API check confirmed both targets with `up=1`.

Blackbox Exporter adds HTTP checks through the actual internal HTTPS access path. The `blackbox-http` job covers eight services:

| Service | Checked access path |
|---|---|
| Paperless-ngx | Internal HTTPS through Caddy |
| Vaultwarden | Internal HTTPS through Caddy |
| AdGuard web interface | Internal HTTPS through Caddy; does not test DNS service health |
| Homepage | Internal HTTPS through Caddy |
| Grafana | Internal HTTPS through Caddy |
| Prometheus | Internal HTTPS through Caddy |
| WUD | Internal HTTPS through Caddy |
| ntfy | Internal HTTPS through Caddy |

All eight probes were documented with `probe_success=1` and HTTP 200 on 09 October 2026. This is a snapshot, not a guarantee of continuous availability or a test of every application function.

The `http_2xx` module follows redirects and verifies TLS using a read-only mounted Caddy root certificate. Blackbox Exporter is reached as `blackbox-exporter:9115` on the shared Docker `monitoring` network; it publishes no host port. Real HTTP targets are generated by Ansible from local variables into `targets/http.yml`; host targets remain separate in `targets/nodes.yml`.

### Grafana dashboards

**Host Overview** provides selectable Node Exporter host metrics.

**Homelab | Service Health V3** is the documented, imported and visually checked service dashboard. It includes:

- UP/DOWN counts, current reachability and observed 24-hour/7-day probe success ratios,
- a service table with HTTP status, HTTPS use and probe duration,
- duration time series and per-service status history,
- TLS certificate lifetime in hours and the five slowest services over 15 minutes,
- a dynamic `service` filter, refresh and measurement notes.

A [Service Health dashboard JSON](services/grafana/dashboards/service-health.json) is already present in the current repository. Its panels match the documented V3 feature set. The local documentation still lists versioning as pending; the exact identity with the user's exported V3 file and automated provisioning are not confirmed here.

Probe duration measures the complete check from the monitoring network, not only application processing time. Historical ratios use observed probes; missing data and time before collection began do not establish full-window availability or an SLA. Caddy's short-lived internal certificates normally renew automatically, so a low remaining lifetime alone does not prove a fault.

### Configuration validation and remaining verification

The Prometheus Ansible role validates configuration with `promtool` before replacing it. The documented negative test rejected invalid configuration with `changed=false`. A HUP reload handler exists in the repository, but execution after a real valid configuration change is still unconfirmed.

Grafana Alerting with ntfy is the next planned step, including a controlled outage and recovery test. Alert delivery, container metrics and monitoring of the Proxmox host are not yet claimed as implemented.

---

## Screenshots

Two real screenshots are planned: Homepage as the service entry point and Grafana Service Health V3 as the operational view. No screenshot files were available with the supplied documents, so no images are embedded yet.

The [screenshot asset guide](docs/assets/screenshots/README.md) defines filenames, captions and publication checks. Add only user-provided captures of the actual environment; review visible addresses, user data and credentials before publishing.

---

## Backup and Recovery

Backup design is treated as part of operating the platform rather than as an optional addition.

Important application data is backed up using Restic to network storage.

Current backup principles include:

- encrypted Restic repositories,
- separate backup targets for important applications,
- automated execution through systemd timers,
- retention policies,
- database-aware backups where necessary,
- non-destructive restore tests.

Paperless and Vaultwarden backups have both been restored successfully in controlled smoke tests.

The restore tests use temporary directories and verify representative critical data without overwriting production files.

This means the backup process has been tested beyond simply confirming that backup jobs complete successfully.

---

## Repository Structure

```text
homelab-platform/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── cd.yml
│
├── automation/
│   └── ansible/
│       ├── collections/
│       ├── inventory/          # includes group_vars/
│       ├── playbooks/
│       └── roles/
│
├── docs/
│   ├── architecture.md
│   ├── firewall.md
│   └── assets/screenshots/
│
├── services/
│   ├── adguard/
│   ├── blackbox-exporter/
│   ├── caddy/
│   ├── grafana/                 # includes dashboard JSON
│   ├── homepage/
│   ├── node-exporter/
│   ├── ntfy/
│   ├── paperless/
│   ├── prometheus/
│   ├── vaultwarden/
│   └── wud/
│
├── .gitignore
├── .yamllint
└── README.md
```

---

## Git Workflow

Relevant changes follow a branch-based workflow:

```text
main
  │
  └── feature / refactor branch
             │
             ▼
          Changes
             │
             ▼
          Local test
             │
             ▼
           Commit
             │
             ▼
            Push
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
             CD
```

Direct changes to `main` are avoided for normal development work.

This provides a practical environment for learning and applying pull requests, automated validation and controlled deployments.

---

## Security Principles

The repository follows several basic security rules:

- no passwords in Git,
- no private SSH keys in Git,
- no API tokens in Git,
- no real `.env` files in Git,
- no real internal inventory in the public repository,
- generic `.example` files for required configuration,
- dedicated SSH credentials for automation,
- dedicated automation accounts,
- minimal GitHub Actions permissions,
- self-hosted runners isolated from normal management systems,
- no self-hosted execution for pull requests,
- production services excluded from automatic deployment until the deployment process has been proven in development.

Security controls are expanded when they provide concrete value rather than being added only for complexity.

---

## Current Status

| Area | Status |
|---|---|
| Proxmox virtualization | Implemented |
| Development VM | Implemented |
| Operations / Ansible VM | Implemented |
| Dedicated GitHub Actions runner VM | Implemented |
| Docker provisioning with Ansible | Implemented |
| Reusable Ansible roles | Implemented |
| Git branch / PR workflow | Implemented |
| GitHub Actions CI | Implemented |
| YAML validation | Implemented |
| Ansible syntax validation | Implemented |
| Docker Compose validation | Implemented |
| Self-hosted CD runner | Implemented |
| GitHub → Runner → Ansible → DEV connectivity | Verified |
| Automated application deployment through CD | Not confirmed; current workflow is connectivity-only |
| Restic backup automation | Implemented |
| Restore smoke tests | Verified |
| Monitoring on DEV | Operational in documented state |
| Node Exporter targets | DEV and Raspberry Pi verified |
| Blackbox HTTPS checks | Eight internal services verified on 09 October 2026 |
| Grafana dashboards | Host Overview and Service Health V3 visually checked |
| Prometheus configuration validation | Invalid configuration rejection verified |
| Prometheus reload after a real change | Pending verification |
| Grafana Alerting → ntfy | Planned |
| Dashboard provisioning | Not confirmed |
| Kubernetes / k3s | Planned |
| Terraform / Cloud IaC | Planned |

---

## Current CI/CD Flow

The currently verified workflow is:

```text
Developer
    │
    ▼
Feature Branch
    │
    ▼
Pull Request
    │
    ▼
GitHub-hosted CI
    │
    ├── YAML validation
    ├── Ansible syntax validation
    └── Docker Compose validation
    │
    ▼
Merge to main
    │
    ├──────────────► CI
    │
    ▼
CD Workflow
    │
    ▼
runner01
    │
    ├── Checkout
    ├── Install Ansible collections
    └── Load local inventory
    │
    ▼
SSH / Ansible
    │
    ▼
dev01
    │
    ▼
Connectivity verified
```

The next milestone extends the final step from a connectivity test to an actual Ansible-managed deployment.

---

## Roadmap

The current implementation order is deliberately incremental.

### Next

- configure Grafana Alerting with ntfy for sustained service failures (approximately two minutes), then test notification and recovery,
- confirm the V3 export against the committed dashboard and make provisioning reproducible where useful,
- verify the Prometheus reload handler after a real valid configuration change,
- complete the remote file-existence check from the configuration validation negative test,
- add the real Homepage and Grafana screenshots,
- extend the connectivity-only CD workflow with a controlled service deployment and verify the resulting state.

### Later

- container-level metrics with cAdvisor and monitoring of the Proxmox host,
- monitoring retention and backup/restore coverage,
- review obsolete Docker-network firewall rules after confirming active paths,
- additional alerting components only where needed,
- further backup coverage and restore testing,
- tighter deployment controls where useful,
- k3s/Kubernetes,
- Terraform,
- a small reproducible cloud environment.

Large additional platforms are intentionally avoided until they solve a concrete problem or provide a clear learning objective.

---

## Why This Project Exists

This repository documents the transition from manually operated self-hosted services toward a reproducible platform workflow.

The important part is therefore not the number of applications being hosted.

The project is intended to demonstrate the progression from:

```text
Manual server administration
          ↓
Docker Compose
          ↓
Structured Git repository
          ↓
Pull Requests
          ↓
Configuration management with Ansible
          ↓
Automated CI validation
          ↓
Isolated Continuous Deployment
          ↓
Monitoring and recovery
          ↓
Infrastructure as Code
```

Each layer is introduced only after the previous one is understood and operationally useful.

The result is a continuously evolving environment for practical DevOps and platform engineering experience rather than a static collection of configuration files.

---

## Documentation

A more detailed description of the technical design and its trust boundaries is available in:

[docs/architecture.md](docs/architecture.md)

Supporting documentation may describe earlier milestones; the dated current-state sections in this README distinguish today's documented runtime state from implemented repository configuration and planned work.

The repository intentionally contains only information suitable for publication. Concrete private infrastructure details, credentials, internal inventories and operational secrets are maintained outside the public repository.
