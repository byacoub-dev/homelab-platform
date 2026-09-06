# Firewall Rules

This document describes the firewall approach used by the Ansible automation.

Service ports are not opened generally to the network. Access is restricted to explicitly configured trusted systems, such as the reverse proxy.

Environment-specific addresses are not stored in this repository. They are supplied through local Ansible variables and excluded from version control.

## Development hosts

The following connections are currently required for services running on development hosts:

| Source | Target | Port | Protocol | Purpose |
|---|---|---:|---|---|
| Reverse proxy | Development host | `3000` | TCP | What's Up Docker |
| Reverse proxy | Development host | `3001` | TCP | Grafana |
| Reverse proxy | Development host | `9090` | TCP | Prometheus |
| Administration network | Development host | `22` | TCP | SSH |

Node Exporter on port `9100` is used for monitoring. It does not need to be exposed through the reverse proxy when Prometheus can access it directly within the network.

## Ansible configuration

Firewall rules are managed through the Ansible `firewall` role:

```text
automation/ansible/roles/firewall/
```

Environment-specific values, such as the IP address of the reverse proxy, are supplied through the local configuration:

```text
automation/ansible/group_vars/development.yml
```

For example:

```yaml
reverse_proxy_ip: "192.168.1.10"
```

The value shown above is only an example. The actual environment-specific configuration is stored locally and excluded from Git.

A public example configuration can be provided through:

```text
automation/ansible/group_vars/development.yml.example
```

This keeps the firewall configuration reproducible while avoiding host-specific addresses in the public repository.

## Applying the firewall configuration

The firewall configuration is applied using:

```bash
ansible-playbook playbooks/configure-firewall.yml -K
```

The `-K` option asks for the privilege escalation password required by tasks using `become: true`.

The Ansible role ensures that the required rules exist and enables UFW. Re-running the playbook is idempotent and should therefore not create duplicate firewall rules.

The resulting configuration can be verified on the target host with:

```bash
sudo ufw status numbered
```

Only explicitly required service connections should be allowed. Additional ports should be added through the Ansible role rather than manually modifying UFW on individual hosts.
