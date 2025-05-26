# Kurtosis Sync Test Role

This role sets up the Kurtosis Sync Test service, which runs the oneliner.sh script as a systemd service.

## Requirements

- Kurtosis should be installed on the target host
- Docker should be installed
- VictoriaMetrics credentials should be available in the Ansible variables

## Role Variables

The role uses the following variables defined in group_vars:

- `prometheus_remote_push_url`: URL for VictoriaMetrics
- `secret_prometheus_remote_write.username`: Username for VictoriaMetrics authentication
- `secret_prometheus_remote_write.password`: Password for VictoriaMetrics authentication

## Example Usage

Include this role in your playbook:

```yaml
- hosts: servers
  roles:
    - role: kurtosis_sync_test
      tags: [kurtosis-sync]
```