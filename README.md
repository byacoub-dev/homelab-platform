# Homelab Platform

A practical DevOps homelab for learning and implementing containerized infrastructure, configuration management, CI/CD, monitoring, networking, backup and recovery.

The project is not intended to be a collection of self-hosted applications. Its primary purpose is to build a small but realistic platform in which infrastructure changes are versioned, validated, automated and documented.

The environment is built around Docker Compose, Ansible, GitHub Actions, Proxmox, Prometheus and Grafana. Stable infrastructure services are separated from development and automation workloads, while the public repository contains only reusable configuration and generic examples.

> **Current focus:** Building a controlled CI/CD path from GitHub to the development environment. Pull requests are validated on GitHub-hosted runners, while deployments after a merge to `main` use a dedicated and isolated self-hosted runner inside the homelab.

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
                                      Docker Services


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

Deployment jobs use a dedicated self-hosted GitHub Actions runner named `runner01`.

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

The next step is to replace the connectivity-only test with the first controlled deployment of a low-risk service such as Node Exporter.

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
│   └── hosts.yml.example
├── group_vars/
│   └── development.yml.example
├── playbooks/
│   ├── bootstrap.yml
│   ├── configure-firewall.yml
│   ├── deploy-grafana.yml
│   ├── deploy-node-exporter.yml
│   ├── deploy-prometheus.yml
│   ├── deploy-wud.yml
│   └── system-info.yml
└── roles/
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
group_vars/
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

The monitoring stack is based on:

- Prometheus,
- Grafana,
- Node Exporter.

The previously working monitoring architecture followed:

```text
Node Exporter
      │
      ▼
 Prometheus
      │
      ▼
   Grafana
```

Prometheus uses file-based service discovery for host-specific targets. Real target definitions remain local, while example files document the expected structure.

Monitoring services are currently being moved into the new Proxmox-based development environment.

Node Exporter is planned as the first service to be deployed through the new CD pipeline.

Further planned observability improvements include:

- additional Node Exporter targets,
- container metrics,
- Alertmanager,
- ntfy notifications,
- meaningful alert thresholds,
- filesystem and disk I/O visibility.

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
│       ├── group_vars/
│       ├── inventory/
│       ├── playbooks/
│       └── roles/
│
├── docs/
│   └── architecture.md
│
├── services/
│   ├── adguard/
│   ├── caddy/
│   ├── grafana/
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
| Automated application deployment through CD | In progress |
| Restic backup automation | Implemented |
| Restore smoke tests | Verified |
| Monitoring migration to DEV | In progress |
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

- deploy Node Exporter to the development environment through CD,
- verify the deployment after the workflow completes,
- restore/deploy Prometheus and Grafana to the development environment,
- extend monitoring to additional hosts,
- introduce meaningful alerting.

### Later

- container-level metrics,
- Alertmanager with ntfy,
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

`docs/architecture.md`

The repository intentionally contains only information suitable for publication. Concrete private infrastructure details, credentials, internal inventories and operational secrets are maintained outside the public repository.
