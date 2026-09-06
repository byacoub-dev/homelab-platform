# Ansible Automation

This directory contains the Ansible automation used to provision and manage Docker-based development hosts.

The configuration is intentionally kept independent from the concrete homelab infrastructure. Hostnames, IP addresses, usernames and environment-specific values are supplied through local inventory and group variable files that are not committed to the repository.

## Structure

```text
automation/ansible/
├── ansible.cfg
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

## Responsibilities

### `common`

Installs basic packages and prepares the target system for further automation.

### `docker`

Installs Docker Engine and Docker Compose and adds the deployment user to the Docker group.

### `firewall`

Configures UFW and restricts service access to the configured reverse proxy.

### `wud`

Deploys What's Up Docker and prepares its persistent application data.

### `node_exporter`

Deploys Node Exporter for host metrics.

### `prometheus`

Deploys Prometheus and generates the Node Exporter target configuration dynamically from Ansible facts.

### `grafana`

Deploys Grafana and supports restoring existing application data before the initial deployment.

## Local configuration

Create the local inventory from the supplied example:

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
```

Example inventory:

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
# IP address of the reverse proxy that is allowed to access exposed services.
reverse_proxy_ip: "192.168.1.10"
```

The local `hosts.yml` and `development.yml` files are excluded from Git. This keeps the automation reusable while preventing concrete infrastructure values from being stored in the public repository.

## Usage

All commands in this section are executed from the `automation/ansible` directory.

Test connectivity to the configured hosts:

```bash
ansible all -m ping
```

Provision a development host:

```bash
ansible-playbook playbooks/bootstrap.yml -K
```

Deploy an individual service:

```bash
ansible-playbook playbooks/deploy-prometheus.yml -K
```

Configure the firewall:

```bash
ansible-playbook playbooks/configure-firewall.yml -K
```

The `-K` option asks for the privilege escalation password required by tasks using `become: true`.

## Deployment approach

The automation separates infrastructure-specific configuration from reusable deployment logic.

Ansible uses the local inventory and group variables to determine the target system and environment-specific values. The individual roles then prepare the host, deploy the required Docker Compose configuration and start the corresponding services.

Service-specific Compose files remain under the repository's `services/` directory and are copied to the target host during deployment.

This keeps the Docker configuration and Ansible automation separated while still allowing the complete deployment process to be reproduced.

## Firewall

UFW rules are managed through the `firewall` role.

Service ports are not opened generally to the network. Access to services such as Grafana, Prometheus and What's Up Docker can instead be restricted to the configured reverse proxy.

The reverse proxy address itself is supplied through the local `group_vars/development.yml` file and is therefore not hard-coded into the role.

SSH remains available for host administration.

## Secrets

Passwords, tokens and other secrets are not stored in the repository.

Environment-specific credentials must be supplied separately before deployment. For example, the Grafana administrator password is passed to Ansible through an environment variable rather than being committed to Git.

Example files contain placeholders only and can safely be used as templates for local configuration.
