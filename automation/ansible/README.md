# Ansible Automation

This directory contains the Ansible automation used to provision and manage Docker-based development hosts.

The automation is intentionally separated from the concrete homelab infrastructure. Hostnames, IP addresses, usernames, credentials and other environment-specific values are supplied through local inventory and variable files that are not committed to the repository.

Ansible is currently used in two ways:

- manually from the dedicated operations host,
- automatically through the isolated GitHub Actions CD runner.

Both paths use the same version-controlled playbooks and roles.

---

## Architecture

The current automation model separates human-operated infrastructure management from automated deployment:

```text
Manual Operations

Administrator
     │
     ▼
   ops01
     │
   Ansible
     │
     ▼
   dev01


Automated Deployment

GitHub
   │
   ▼
runner01
   │
   Ansible
   │
   ▼
 dev01
```

`ops01` is the normal Ansible control node used for manual administration and troubleshooting.

`runner01` is a separate virtual machine dedicated to trusted GitHub Actions CD jobs. It maintains its own local inventory and dedicated SSH deployment credentials.

This separation prevents the repository-controlled execution environment from sharing the normal administrative control node.

---

## Structure

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

---

## Responsibilities

### `common`

Installs basic packages and prepares the target system for further automation.

### `docker`

Installs Docker Engine and Docker Compose and prepares the deployment user for Docker management.

### `firewall`

Configures UFW and restricts exposed service ports to explicitly allowed systems such as the reverse proxy.

Firewall policy remains part of the desired host configuration instead of being maintained manually on individual systems.

### `wud`

Deploys What's Up Docker and prepares its persistent application data.

The role has already been used to reproduce the service on the current development host.

### `node_exporter`

Deploys Node Exporter for host-level metrics.

Node Exporter is intended to become the first service deployed automatically through the GitHub Actions CD path.

### `prometheus`

Deploys Prometheus and generates the Node Exporter target configuration dynamically from Ansible information and environment-specific variables.

### `grafana`

Deploys Grafana and supports restoring existing application data before the initial deployment.

---

## Collections

External Ansible collections required by the project are declared in:

```text
collections/requirements.yml
```

The current automation uses collections including:

```text
community.docker
community.general
```

Dependencies can be installed with:

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

Keeping these dependencies in the repository makes the Ansible environment reproducible across manual administration, CI and CD.

---

## Local Configuration

Real infrastructure values are deliberately excluded from the public repository.

Create the local inventory from the supplied example:

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
```

Example:

```yaml
---
all:
  children:
    development:
      hosts:
        dev-host:
          ansible_host: dev-host.example.local
          ansible_user: your-user
          service_bind_address: 192.168.1.60
```

Environment-specific variables can be created from the supplied example:

```bash
cp group_vars/development.yml.example group_vars/development.yml
```

Example:

```yaml
---
reverse_proxy_ip: "192.168.1.10"
```

The values above are examples only.

The actual files:

```text
inventory/hosts.yml
group_vars/development.yml
```

are excluded from Git.

This allows the repository to document the required configuration structure without exposing the real network layout.

---

## Manual Usage

Manual Ansible administration is performed from the operations environment.

All commands in this section are executed from:

```text
automation/ansible/
```

Test connectivity:

```bash
ansible all -m ping
```

Inspect basic system information:

```bash
ansible-playbook playbooks/system-info.yml
```

Provision a development host:

```bash
ansible-playbook playbooks/bootstrap.yml -K
```

Configure the firewall:

```bash
ansible-playbook playbooks/configure-firewall.yml -K
```

Deploy an individual service:

```bash
ansible-playbook playbooks/deploy-prometheus.yml -K
```

The `-K` option asks for the privilege escalation password required by tasks using `become: true`.

---

## Automated Usage

The same Ansible automation is also used by the GitHub Actions CD workflow.

The automated path is:

```text
Merge to main
      │
      ▼
GitHub Actions
      │
      ▼
Self-hosted runner
      │
      ├── Checkout repository
      ├── Install Ansible collections
      ├── Load runner-local inventory
      └── Execute Ansible
              │
              ▼
      Development Host
```

The self-hosted runner maintains its real inventory locally instead of retrieving infrastructure-specific values from Git.

Conceptually:

```text
$HOME/ansible/
└── hosts.yml
```

The runner also uses dedicated SSH deployment credentials and a dedicated automation account on the target host.

The current CD workflow validates the complete connection path through an Ansible ping.

The next stage is to use the same path for the first real service deployment.

---

## CI and CD Responsibilities

CI and CD deliberately have different responsibilities.

### CI

Pull requests are validated on GitHub-hosted runners.

The CI workflow checks:

- YAML syntax and style,
- Ansible playbook syntax,
- Docker Compose configuration.

CI does not require access to the private network.

```text
Pull Request
     │
     ▼
GitHub-hosted Runner
     │
     ▼
Validation
```

### CD

CD runs only after trusted changes reach `main` or when manually triggered.

```text
Trusted main
     │
     ▼
Self-hosted Runner
     │
     ▼
Ansible
     │
     ▼
Development Environment
```

The self-hosted runner is intentionally not used for pull-request execution.

This is especially important because the repository is public.

---

## Deployment Approach

The automation separates three concerns:

```text
services/
    │
    └── Docker Compose and application configuration

automation/ansible/
    │
    └── host preparation and deployment logic

.github/workflows/
    │
    └── validation and deployment orchestration
```

Service-specific Compose files remain under the repository's `services/` directory.

Ansible copies or renders the required configuration on the target system and manages the corresponding Docker Compose project.

The target host then follows the general structure:

```text
/srv/stacks/<service>
```

for deployed configuration and:

```text
/srv/appdata/<service>
```

for persistent application data.

This keeps version-controlled deployment configuration separate from runtime state.

---

## Idempotency

The automation is designed to be idempotent where practical.

Once a host already matches the desired state, running the same playbook again should not introduce unnecessary changes.

Conceptually:

```text
First run
changed > 0

Second run
changed = 0
```

This behavior has already been verified with existing service automation.

Idempotency is particularly important for CD because deployment should converge a system toward the desired state instead of depending on a one-time sequence of manual commands.

---

## Firewall

UFW rules are managed through the `firewall` role.

Service ports are not opened generally to the network.

Access to services such as Grafana, Prometheus and What's Up Docker can instead be restricted to explicitly configured systems such as the central reverse proxy.

Environment-specific addresses are supplied through local Ansible variables rather than being hard-coded into the role.

SSH remains available where required for administration and deployment automation.

The detailed firewall model is documented in:

```text
docs/firewall.md
```

---

## Secrets

Passwords, tokens, private SSH keys and other secrets are not stored in the repository.

Environment-specific credentials must be supplied separately before deployment.

Example files contain placeholders only.

The general rule is:

```text
Repository
├── .env.example
├── hosts.yml.example
└── development.yml.example

Local Environment
├── .env
├── hosts.yml
├── development.yml
└── private credentials
```

Only the first group is version-controlled.

---

## Security Model

The repository is public, therefore automated access to the internal environment is deliberately restricted.

The trust model is:

```text
                  Public Repository
                         │
                  Pull Request
                         │
                         ▼
                GitHub-hosted CI


──────────────────── Trust Boundary ────────────────────


                    Trusted main
                         │
                         ▼
                Self-hosted Runner
                         │
                  SSH / Ansible
                         │
                         ▼
                 Development Host
```

The self-hosted runner is isolated in its own virtual machine and uses dedicated deployment credentials.

It is not installed on the normal operations host.

Automatic deployment to stable production services is currently excluded.

---

## Current State

The following Ansible capabilities are currently implemented:

| Capability | State |
|---|---|
| Base host preparation | Implemented |
| Docker provisioning | Implemented |
| UFW configuration | Implemented |
| WUD deployment | Implemented and tested |
| Node Exporter role | Implemented |
| Prometheus role | Implemented |
| Grafana role | Implemented |
| Local/private inventory separation | Implemented |
| Public example configuration | Implemented |
| GitHub Actions syntax validation | Implemented |
| Self-hosted Ansible execution path | Verified |
| Automated service deployment through CD | Next milestone |

The immediate next step is to use Node Exporter as the first low-risk service deployed through the existing CD path.
