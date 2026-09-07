# Architecture

This document describes the technical architecture, design decisions, trust boundaries and deployment model of the Homelab Platform.

The repository represents a practical DevOps and platform engineering environment built around containerized services, configuration management, CI/CD, monitoring and recovery.

The architecture deliberately separates reusable configuration from the concrete private infrastructure. Host-specific addresses, credentials, inventories and secrets are therefore not part of the public repository.

---

## 1. Design Goals

The platform is designed around the following principles:

- reproducible infrastructure and service configuration,
- clear separation between configuration and persistent data,
- Git as the source of truth for reusable configuration,
- automated validation before changes are merged,
- controlled deployment after changes are accepted,
- separation of CI and CD trust boundaries,
- isolated environments for development, operations and automation,
- reusable Ansible roles instead of host-specific scripts,
- centralized internal DNS and reverse proxying,
- monitoring based on operational requirements,
- encrypted backups with practical restore verification,
- no secrets or private infrastructure details in the public repository,
- incremental introduction of additional tooling.

The objective is not to reproduce a large enterprise platform at small scale.

Instead, the environment is intentionally kept understandable enough that every component can be operated, debugged and explained.

---

## 2. High-Level Architecture

The homelab consists of two primary infrastructure areas:

1. a Proxmox virtualization host,
2. a Raspberry Pi providing stable 24/7 infrastructure services.

The virtualization environment contains separate virtual machines for development, operations and Continuous Deployment.

```text
                        Homelab Network
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
        Proxmox Host                     Raspberry Pi
              │                               │
      ┌───────┼────────┐              Stable 24/7 Services
      │       │        │                      │
      ▼       ▼        ▼                ┌─────┼──────────────┐
    dev01   ops01   runner01            │     │              │
      │       │        │             AdGuard Caddy      Applications
      │       │        │
      │       │        └── GitHub Actions CD
      │       │
      │       └── Manual Ansible Operations
      │
      └── Docker / Development Services
```

The physical hypervisor remains intentionally lightweight. Application workloads are not intended to run directly on the Proxmox host.

This provides a clean separation between:

```text
Hypervisor
    │
    ├── Development
    ├── Operations
    └── Deployment Automation
```

The Raspberry Pi remains independent from the development environment and hosts infrastructure that should be available continuously.

---

## 3. Host Responsibilities

### Proxmox Host

The physical Proxmox system is responsible only for virtualization.

Its responsibilities include:

- VM lifecycle,
- virtual networking,
- compute and storage allocation,
- infrastructure isolation.

Docker applications and automation workloads are deliberately kept out of the hypervisor itself.

This reduces coupling between the virtualization layer and the applications running above it.

---

### dev01

`dev01` is the current development and deployment target.

It is an Ubuntu Server VM running Docker and serves as the first environment managed through Ansible and the CI/CD pipeline.

Its responsibilities include:

- Docker Engine,
- Docker Compose,
- development services,
- monitoring services,
- testing Ansible-managed deployments,
- receiving deployments from the CD pipeline.

Service configuration originates from Git, while persistent application data remains outside the repository.

The general filesystem model is:

```text
/srv/stacks/<service>    → deployed service configuration
/srv/appdata/<service>   → persistent application data
```

This allows service definitions to be replaced or redeployed independently from application state.

---

### ops01

`ops01` is the normal operations and Ansible control node.

It is used for:

- Git operations,
- manual Ansible execution,
- infrastructure administration,
- testing automation before it becomes part of CD,
- troubleshooting.

The general administrative path is:

```text
Administrator
     │
     ▼
   ops01
     │
   Ansible
     │
     ▼
   dev01
```

`ops01` is deliberately not used as the GitHub Actions Self-hosted Runner.

This separation became particularly important because the repository is public.

A CI/CD runner executes repository-controlled code and therefore represents a different trust domain than an administrative control node.

---

### runner01

`runner01` is a dedicated Ubuntu VM used exclusively for trusted internal GitHub Actions CD jobs.

Its responsibilities are intentionally narrow:

- connect outbound to GitHub,
- receive approved CD jobs,
- checkout the repository,
- install declared Ansible dependencies,
- use a local private inventory,
- connect to deployment targets using dedicated SSH credentials,
- execute controlled Ansible deployments.

The runner is not intended to host applications.

It is also not intended to become a general-purpose management server.

The separation can be summarized as:

```text
ops01
└── human-controlled infrastructure administration

runner01
└── repository-controlled deployment automation
```

This prevents the CI/CD execution environment from being unnecessarily combined with the normal administrative environment.

---

### Raspberry Pi

The Raspberry Pi provides stable infrastructure and application services intended to remain available independently from the development environment.

Its current responsibilities include services such as:

- AdGuard Home,
- Caddy,
- Homepage,
- Paperless-ngx,
- Vaultwarden,
- ntfy.

Caddy acts as the central reverse proxy.

AdGuard provides internal DNS.

The Raspberry Pi therefore forms an infrastructure layer that remains operational even while development VMs are being changed or rebuilt.

Automatic CD deployments to these services are intentionally excluded at the current stage.

The first automated deployments are restricted to the development environment.

---

## 4. Repository Architecture

The repository follows a service-centric rather than host-centric structure.

```text
homelab-platform/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── cd.yml
│
├── automation/
│   └── ansible/
│       ├── ansible.cfg
│       ├── collections/
│       │   └── requirements.yml
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

The three major areas have different responsibilities:

```text
services/
└── application definitions

automation/
└── infrastructure and deployment automation

.github/
└── validation and deployment orchestration
```

This separation prevents Docker configuration, infrastructure automation and pipeline logic from becoming tightly coupled.

---

## 5. Service-Centric Deployment Model

Service definitions are independent from the hosts on which they currently run.

A typical service directory contains:

```text
services/<service>/
├── compose.yml
├── .env.example
└── optional additional configuration
```

Examples of additional configuration include:

- Prometheus configuration,
- Prometheus target examples,
- Caddy configuration,
- application-specific configuration templates.

The repository intentionally does not contain structures such as:

```text
deployments/dev01/
deployments/raspberrypi/
```

because that would unnecessarily bind reusable service definitions to the current physical infrastructure.

Instead:

```text
Service definition
       │
       ▼
Environment-specific configuration
       │
       ▼
Selected deployment target
```

The same service definition can therefore be deployed to another compatible Docker host without restructuring the repository.

---

## 6. Configuration and Persistent Data

Configuration and runtime state are treated as separate concerns.

Git contains:

- Docker Compose definitions,
- Ansible roles,
- Ansible playbooks,
- example configuration,
- workflow definitions,
- documentation.

Git does not contain:

- databases,
- uploaded files,
- application state,
- private `.env` files,
- credentials,
- private SSH keys,
- private inventories.

Persistent application data follows the general pattern:

```text
/srv/appdata/<service>
```

Deployed service configuration on managed Docker hosts follows:

```text
/srv/stacks/<service>
```

Conceptually:

```text
                  Git Repository
                       │
                       │ deployment
                       ▼
              /srv/stacks/service
                       │
                       │ container mounts
                       ▼
                 Docker Container
                       │
                       │ persistent state
                       ▼
             /srv/appdata/service
```

The result is that containers and deployment directories can be recreated without deleting application state.

---

## 7. Environment-Specific Configuration

Private infrastructure information is deliberately separated from the public repository.

The public repository contains example files such as:

```text
inventory/
└── hosts.yml.example
```

while the actual environment uses:

```text
inventory/
├── hosts.yml          # local / ignored
└── hosts.yml.example  # public
```

The same model is used for environment variables:

```text
group_vars/
├── development.yml          # local / ignored
└── development.yml.example  # public
```

This allows the repository to document which values are required without exposing the concrete infrastructure.

Examples of information deliberately kept outside the public repository include:

- internal IP addresses,
- deployment usernames where unnecessary,
- passwords,
- API tokens,
- SSH private keys,
- actual `.env` files,
- infrastructure-specific secrets.

---

## 8. Ansible Architecture

Ansible provides configuration management and deployment automation.

The current structure is:

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

Playbooks describe intent while roles implement reusable behavior.

For example:

```text
deploy-wud.yml
      │
      ▼
   wud role
      │
      ├── create directories
      ├── render configuration
      ├── prepare persistent data
      └── manage Docker Compose project
```

The same principle applies to the other service roles.

---

## 9. Ansible Dependency Management

External Ansible collections are declared in:

```text
automation/ansible/collections/requirements.yml
```

The project currently uses collections including:

```text
community.docker
community.general
```

The dependency file is used by both development and CI/CD environments.

This avoids relying on undocumented packages that happen to be installed on one particular control node.

Conceptually:

```text
requirements.yml
      │
      ├── ops01
      │
      ├── CI
      │
      └── runner01
```

All environments can therefore install the same declared Ansible dependencies.

---

## 10. Idempotency

Ansible automation is designed to be idempotent where practical.

Running the same playbook multiple times should result in:

```text
First run
changed > 0

Second run
changed = 0
```

when the desired state has already been reached.

This has already been tested with existing automation.

Idempotency is important because CD should describe desired state rather than blindly executing a sequence of imperative shell commands.

---

## 11. Git Workflow

Changes follow a branch-based workflow.

```text
main
 │
 └── feature / refactor branch
             │
             ▼
          Changes
             │
             ▼
        Local validation
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
        Review / Merge
             │
             ▼
             CD
```

Normal development work is therefore not performed directly on `main`.

This provides a natural point at which automated validation can occur before deployment becomes possible.

---

## 12. Continuous Integration

Continuous Integration runs on GitHub-hosted infrastructure.

The CI workflow is responsible for validating repository content without requiring access to the private homelab network.

Current validation includes:

- YAML linting,
- Ansible syntax checking,
- Docker Compose validation.

The flow is:

```text
Pull Request
      │
      ▼
GitHub-hosted Runner
      │
      ├── Checkout
      ├── Install dependencies
      ├── yamllint
      ├── Ansible syntax-check
      └── docker compose config
      │
      ▼
    Result
```

The workflow installs the Ansible collections defined in the repository before syntax validation.

For Compose validation, example environment files can be used temporarily where required so that configuration can be parsed without exposing real environment values.

The CI runner does not require:

- SSH access to the homelab,
- internal inventory,
- private deployment keys,
- access to application data.

This is intentional.

---

## 13. Continuous Deployment

Continuous Deployment is implemented separately from CI.

The current CD architecture is:

```text
Merge to main
      │
      ▼
GitHub
      │
      ▼
runner01
      │
      ├── Checkout repository
      ├── Install Ansible collections
      ├── Load local inventory
      └── Execute Ansible
              │
              ▼
            dev01
```

The initial CD workflow intentionally performs only a connectivity verification.

The purpose of this first stage was to validate the complete transport and trust chain before allowing the workflow to modify systems.

The following path has been successfully verified:

```text
GitHub
   │
   ▼
runner01
   │
   ▼
Ansible
   │
   ▼
SSH
   │
   ▼
dedicated automation account
   │
   ▼
dev01
   │
   ▼
pong
```

The next step is to extend this path with the first actual service deployment.

Node Exporter is intended as the first deployment target because it is comparatively low risk and largely stateless.

---

## 14. CI/CD Separation

CI and CD deliberately operate in different trust domains.

```text
                    CI

Feature Branch
      │
      ▼
Pull Request
      │
      ▼
GitHub-hosted Runner
      │
      ▼
Repository Validation


                    CD

Trusted main
      │
      ▼
Self-hosted runner01
      │
      ▼
Private Infrastructure
```

CI answers:

> Is this repository change structurally valid?

CD answers:

> Should the accepted desired state now be applied to the development environment?

Keeping these responsibilities separate reduces the privileges required by CI.

---

## 15. Public Repository Trust Boundary

The repository is public.

Running a self-hosted GitHub Actions Runner for a public repository therefore requires special care.

A self-hosted runner executes workflow instructions inside infrastructure controlled by the repository owner.

Allowing arbitrary pull requests to execute on that runner could create a path from untrusted repository contributions into the private network.

The architecture therefore establishes a clear trust boundary:

```text
                    PUBLIC / UNTRUSTED

                           GitHub
                              │
                       Pull Request
                              │
                              ▼
                    GitHub-hosted CI
                              │
                     Repository checks


──────────────────────── TRUST BOUNDARY ────────────────────────


                        Trusted main
                              │
                              ▼
                          runner01
                              │
                       SSH / Ansible
                              │
                              ▼
                            dev01
```

The CD workflow intentionally has no `pull_request` trigger.

It is currently triggered only by:

```text
push → main
workflow_dispatch
```

This behavior was tested when the CD workflow itself was introduced.

During the pull request:

```text
GitHub-hosted CI → executed
Self-hosted CD   → not executed
```

After the merge:

```text
push to main
      │
      ├── CI
      │
      └── CD → runner01
```

The first CD run completed successfully.

---

## 16. Self-hosted Runner Isolation

The Self-hosted Runner is placed in its own VM instead of being installed on `ops01`.

This creates an additional isolation boundary:

```text
                 Proxmox
                    │
       ┌────────────┼────────────┐
       │            │            │
     dev01        ops01       runner01
       │            │            │
 Development    Operations    GitHub CD
```

If the runner is compromised, the objective is to limit the affected environment rather than exposing the primary operations host directly.

The runner therefore receives only the capabilities required for deployment.

The current design uses:

- dedicated VM,
- dedicated SSH key,
- dedicated target account,
- local inventory,
- restricted workflow triggers,
- no automatic production deployment.

Further hardening can be introduced as the deployment model becomes stable.

---

## 17. Deployment Authentication

`runner01` uses a dedicated Ed25519 SSH deployment key.

The private key remains local to the runner.

The corresponding public key is authorized for a dedicated automation account on the development target.

Conceptually:

```text
runner01
    │
    │ dedicated SSH key
    ▼
automation account
    │
    │ privilege escalation
    ▼
dev01
```

This avoids reusing personal SSH credentials or the credentials used by `ops01`.

The automation account exists only for machine-driven infrastructure management.

---

## 18. Local Runner Inventory

The CD runner maintains its real inventory locally.

Conceptually:

```text
runner01

$HOME/ansible/
└── hosts.yml
```

The file contains the actual information required to connect to the development target.

It is not part of the Git repository.

The public repository contains only generic inventory examples.

This allows the workflow itself to remain reusable:

```text
GitHub Workflow
      │
      ▼
$HOME/ansible/hosts.yml
      │
      ▼
Environment-specific target
```

---

## 19. Current Deployment Flow

The complete current flow is:

```text
Developer
    │
    ▼
Feature Branch
    │
    ▼
Local Validation
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
GitHub-hosted CI
    │
    ├── YAML validation
    ├── Ansible syntax validation
    └── Docker Compose validation
    │
    ▼
Review
    │
    ▼
Merge to main
    │
    ├──────────────────────► CI
    │
    ▼
CD Workflow
    │
    ▼
runner01
    │
    ├── Checkout repository
    ├── Install Ansible collections
    └── Load private inventory
    │
    ▼
SSH / Ansible
    │
    ▼
dev01
    │
    ▼
Connectivity Verification
```

The final stage will progressively evolve into:

```text
dev01
  │
  ▼
Ansible Role
  │
  ▼
Docker Compose
  │
  ▼
Service
  │
  ▼
Verification
```

---

## 20. Deployment Progression

Deployments are introduced incrementally.

The intended progression is:

```text
Connectivity Test
       │
       ▼
Node Exporter
       │
       ▼
Prometheus
       │
       ▼
Grafana
       │
       ▼
Additional DEV Services
       │
       ▼
Evaluate Production Deployment
```

This deliberately avoids enabling automatic deployment for every service immediately.

Each additional deployment should first demonstrate:

- reproducibility,
- predictable configuration,
- safe handling of persistent data,
- successful post-deployment verification,
- acceptable rollback or recovery options.

---

## 21. Network Architecture

Internal DNS is provided by AdGuard.

HTTP and HTTPS access is centralized through Caddy.

The general request path is:

```text
Client
  │
  │ DNS request
  ▼
AdGuard
  │
  │ internal service address
  ▼
Caddy
  │
  ├──────────────► Local Docker Service
  │
  └──────────────► Remote Internal Backend
```

Service names use the reserved `home.arpa` namespace for the private home network.

This provides readable internal names while avoiding reliance on public DNS.

---

## 22. Reverse Proxy Architecture

Caddy is the central HTTP/HTTPS entry point.

It can proxy to two categories of backend:

```text
                       Caddy
                         │
             ┌───────────┴───────────┐
             │                       │
             ▼                       ▼
   Same-host Docker Service    Remote LAN Service
             │                       │
       Docker DNS                  Host/IP
```

Services running on the same Docker host can be reached through Docker networking.

Services running on another VM are reached through their internal network endpoint.

This distinction is important during troubleshooting because Docker container names are only resolvable within appropriate Docker networks.

---

## 23. Internal TLS

Caddy uses its internal certificate authority for local services.

The conceptual TLS path is:

```text
Client
  │
 HTTPS
  ▼
Caddy
  │
 Internal CA
  ▼
Backend Service
```

Clients must trust the Caddy root certificate to avoid browser certificate warnings.

Certificate trust distribution is treated as a client configuration concern rather than exposing internal services publicly.

---

## 24. Monitoring Architecture

The monitoring stack consists primarily of:

- Node Exporter,
- Prometheus,
- Grafana.

The architecture is:

```text
Host
 │
 ▼
Node Exporter
 │
 │ metrics
 ▼
Prometheus
 │
 │ queries
 ▼
Grafana
```

Prometheus acts as the metrics collection and storage layer.

Grafana acts as the visualization layer.

Node Exporter exposes operating-system metrics.

---

## 25. Prometheus Target Management

Prometheus uses file-based service discovery for host-specific targets.

Conceptually:

```text
prometheus.yml
      │
      ▼
file_sd_configs
      │
      ▼
targets/nodes.yml
```

The real target file remains local and is not committed.

The repository contains a generic example instead.

This follows the same principle used by Ansible inventories:

```text
Reusable logic in Git
Environment-specific values outside Git
```

---

## 26. Observability Roadmap

The monitoring architecture is intended to evolve gradually.

Planned additions include:

```text
Hosts
  │
  ├── Node Exporter
  │
Containers
  │
  ├── Container Metrics
  │
  ▼
Prometheus
  │
  ├── Metrics
  └── Alert Rules
       │
       ▼
   Alertmanager
       │
       ▼
      ntfy

Prometheus
    │
    ▼
 Grafana
```

The objective is not simply to collect more metrics.

Each signal should support an operational question such as:

- Is a host reachable?
- Is CPU or memory pressure abnormal?
- Is disk space becoming critical?
- Is a container repeatedly failing?
- Is a monitored service unavailable?
- Does an operator need to be notified?

---

## 27. Backup Architecture

Backups are considered part of platform operation.

Selected application data is backed up using Restic to network-attached storage.

The conceptual path is:

```text
Application Data
      │
      ▼
Backup Script
      │
      ├── application-aware preparation
      ├── optional database dump
      └── Restic snapshot
              │
              ▼
        Network Storage
```

Restic provides encrypted and deduplicated snapshots.

Backup automation is currently executed using systemd services and timers.

---

## 28. Application-Aware Backups

Different applications require different consistency strategies.

For example, database-backed services may require:

```text
Application
    │
    ▼
Consistent Database Dump
    │
    ▼
Restic Snapshot
```

while other services may be safely stopped briefly during the backup operation.

The important principle is that backup consistency is evaluated per application rather than assuming that copying arbitrary live files always produces a valid backup.

---

## 29. Restore Verification

A successful backup command does not prove that data can actually be restored.

The environment therefore includes non-destructive restore smoke tests.

The general process is:

```text
Restic Repository
       │
       ▼
Temporary Restore Directory
       │
       ├── Verify configuration
       ├── Verify database dump
       └── Verify application data
       │
       ▼
Remove Temporary Restore
```

Production data is not overwritten during these tests.

Restore smoke tests have already been successfully performed for important application data.

This verifies several assumptions simultaneously:

- repository access works,
- repository decryption works,
- snapshots can be read,
- expected files are present,
- representative critical data can be restored.

---

## 30. Security Model

The project follows a pragmatic defense-in-depth approach.

The current layers include:

```text
Public Repository
      │
      ├── no secrets
      ├── no private inventory
      └── example configuration only
      │
      ▼
GitHub-hosted CI
      │
      └── no internal network access required
      │
      ▼
Trusted Merge
      │
      ▼
Isolated runner01
      │
      ├── dedicated VM
      ├── dedicated SSH key
      └── local inventory
      │
      ▼
Dedicated Automation Account
      │
      ▼
Development Environment
```

No single control is considered sufficient by itself.

Instead, several smaller boundaries reduce unnecessary exposure.

---

## 31. Secrets Management Principles

The following data must not be committed:

- passwords,
- API tokens,
- private SSH keys,
- recovery codes,
- real `.env` files,
- private inventories,
- confidential webhook URLs.

The repository may document:

- that a secret is required,
- which variable expects it,
- where it should be supplied,
- what service depends on it.

Example:

```text
.env.example
```

may contain:

```text
ADMIN_PASSWORD=change-me
```

but the actual `.env` file remains local and ignored.

The example must still contain syntactically valid values where applications or CI validators require them.

---

## 32. GitHub Actions Permissions

Workflows use minimal repository permissions where possible.

The CD workflow currently requires only:

```yaml
permissions:
  contents: read
```

The workflow therefore receives the permission necessary to read the repository without unnecessarily requesting write privileges.

Additional permissions should only be introduced when a concrete workflow requires them.

---

## 33. Production Protection

The current automated deployment path targets development infrastructure only.

Stable Raspberry Pi services are excluded.

Current model:

```text
GitHub
   │
   ▼
runner01
   │
   ▼
DEV
```

Not:

```text
GitHub
   │
   ├── DEV
   └── PROD
```

Production automation will only be considered after the development deployment model has proven reliable.

A future model could introduce an explicit approval boundary:

```text
Merge
  │
  ▼
Deploy DEV
  │
  ▼
Verification
  │
  ▼
Manual Approval
  │
  ▼
Deploy PROD
```

This is a future design option rather than part of the current implementation.

---

## 34. Failure Domains

The architecture deliberately creates several independent failure domains.

### Development VM failure

A failure of `dev01` should not take down stable Raspberry Pi services.

### Runner failure

A failure of `runner01` prevents automated CD but does not prevent the services themselves from running.

Manual administration through `ops01` remains separate.

### Operations VM failure

A failure of `ops01` prevents normal manual Ansible administration but does not stop deployed applications.

### Raspberry Pi failure

A Raspberry Pi failure affects centralized DNS, reverse proxy and the applications hosted there and therefore represents an important infrastructure failure domain.

Backup and recovery procedures are particularly relevant for these persistent services.

### Hypervisor failure

A Proxmox host failure affects all VMs running on it and therefore represents the primary virtualization failure domain.

These trade-offs are accepted for a small homelab environment.

---

## 35. Reproducibility Model

The platform aims for progressively increasing reproducibility.

The current layers are:

```text
Service Definition
      │
      ▼
Docker Compose
      │
      ▼
Ansible Deployment
      │
      ▼
GitHub CI Validation
      │
      ▼
GitHub CD Execution
```

A fresh compatible Linux system should increasingly be able to move from:

```text
Fresh OS
```

toward:

```text
Configured Docker Host
      │
      ▼
Deployed Services
```

using version-controlled automation.

Persistent application data remains a separate recovery concern and is restored from backups rather than Git.

---

## 36. Current State

The following architecture components are currently implemented:

| Component | State |
|---|---|
| Proxmox virtualization | Implemented |
| Isolated development VM | Implemented |
| Dedicated operations VM | Implemented |
| Dedicated Self-hosted Runner VM | Implemented |
| Docker provisioning with Ansible | Implemented |
| Reusable Ansible roles | Implemented |
| Service-centric repository | Implemented |
| Branch and Pull Request workflow | Implemented |
| GitHub-hosted CI | Implemented |
| YAML validation | Implemented |
| Ansible syntax validation | Implemented |
| Docker Compose validation | Implemented |
| Self-hosted CD runner | Implemented |
| Isolated CD trust boundary | Implemented |
| GitHub → runner → Ansible → DEV path | Verified |
| Real service deployment through CD | Next milestone |
| Restic backups for selected services | Implemented |
| Restore smoke testing | Verified |
| Monitoring migration | In progress |
| Production CD | Not enabled |
| Kubernetes | Planned |
| Terraform | Planned |

---

## 37. Next Architecture Milestone

The immediate milestone is to turn the successfully tested CD transport path into an actual deployment path.

Current state:

```text
GitHub
  │
  ▼
runner01
  │
  ▼
Ansible
  │
  ▼
dev01
  │
  ▼
Connectivity Test
```

Next state:

```text
GitHub
  │
  ▼
runner01
  │
  ▼
Ansible
  │
  ▼
dev01
  │
  ▼
Node Exporter Role
  │
  ▼
Docker Compose
  │
  ▼
Node Exporter
  │
  ▼
Post-Deployment Verification
```

This will establish the first complete:

```text
Code
 ↓
Review
 ↓
Validation
 ↓
Merge
 ↓
Deployment
 ↓
Verification
```

cycle.

---

## 38. Planned Evolution

Once the initial CD deployment has proven reliable, the platform can evolve incrementally.

The intended progression is:

```text
Current Platform
      │
      ├── Complete DEV CD
      │
      ├── Restore Monitoring Stack
      │
      ├── Improve Alerting
      │
      ├── Expand Recovery Coverage
      │
      ├── Evaluate Production CD
      │
      ├── Kubernetes / k3s
      │
      └── Terraform / Cloud IaC
```

Kubernetes and Terraform are intentionally later stages.

The existing Docker Compose and Ansible environment provides the foundation required to understand why those tools are useful instead of introducing them only for complexity.

---

## 39. Architectural Principles

The current architecture can be summarized by the following rules:

### Git stores desired configuration, not runtime state

```text
Git
├── Compose
├── Ansible
├── CI/CD
└── Documentation

Runtime
├── Databases
├── Uploads
├── Application state
└── Secrets
```

### CI validates before CD deploys

```text
Change
  ↓
CI
  ↓
Merge
  ↓
CD
```

### Untrusted code stays outside the private infrastructure

```text
Pull Request
     ↓
GitHub-hosted Runner
```

### Trusted deployments use an isolated execution environment

```text
main
 ↓
runner01
 ↓
DEV
```

### Operations and automation remain separate

```text
Human Operations → ops01
Automated CD     → runner01
```

### Stable services and development workloads remain separated

```text
Stable Infrastructure → Raspberry Pi
Development           → Proxmox VMs
```

### Persistent data is independent from deployment configuration

```text
/srv/stacks
     │
configuration
     │
     ▼
container
     │
     ▼
/srv/appdata
```

### A backup is not considered proven until restoration works

```text
Backup
  ↓
Restore Test
  ↓
Verified Recovery
```

---

## 40. Architecture Summary

The Homelab Platform has evolved from manually managed Docker services into a small but structured DevOps environment.

The current architecture combines:

- Proxmox for workload isolation,
- Docker Compose for containerized applications,
- Git for version-controlled desired state,
- Ansible for configuration management and deployment,
- GitHub Actions for CI/CD orchestration,
- GitHub-hosted runners for untrusted CI,
- an isolated Self-hosted Runner for trusted internal CD,
- AdGuard for internal DNS,
- Caddy for centralized reverse proxying and local TLS,
- Prometheus and Grafana for observability,
- Restic for encrypted backups,
- practical restore testing for recovery verification.

The resulting architecture currently follows this end-to-end model:

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
             ┌───────────────┼────────────────┐
             │               │                │
          yamllint     Ansible syntax    Compose config
             │               │                │
             └───────────────┼────────────────┘
                             │
                             ▼
                       Review / Merge
                             │
                             ▼
                            main
                             │
                             ▼
                      CD Workflow
                             │
                             ▼
                         runner01
                             │
                    local inventory
                             │
                       SSH / Ansible
                             │
                             ▼
                           dev01
                             │
                             ▼
                     Docker Services
                             │
                             ▼
                        Monitoring


              Stable Infrastructure Services
                             │
                             ▼
                       Raspberry Pi
                  ┌──────────┼───────────┐
                  │          │           │
               AdGuard     Caddy    Applications
                  │          │
                  └────┬─────┘
                       │
                       ▼
                 Internal Clients


                    Persistent Data
                          │
                          ▼
                    Restic Backup
                          │
                          ▼
                   Network Storage
                          │
                          ▼
                   Restore Testing
```

The architecture remains intentionally incremental.

The goal is not maximum complexity. The goal is a platform whose components, security boundaries, deployment path, monitoring and recovery procedures can be understood, reproduced, tested and explained.
