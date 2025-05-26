# Kurtosis Sync Test Setup

This document explains the changes made to the Ansible configuration to run the `oneliner.sh` script as a systemd service.

## Overview

The following changes have been made:

1. Created a new Ansible role `kurtosis_sync_test`
2. Added a systemd service file for running `oneliner.sh`
3. Set up environment variables for VictoriaMetrics authentication

## Setup Steps

1. The role has been added to the main playbook in `playbook.yaml`.

2. To deploy the service:

```bash
cd ansible
ansible-playbook -i inventories.ini playbook.yaml --tags kurtosis-sync
```

## How It Works

1. The role copies the `oneliner.sh` script and necessary files to `/opt/kurtosis-sync-test/`
2. Creates a systemd service (`kurtosis-sync.service`) that runs the script
3. Sets up environment variables for VictoriaMetrics authentication in `/etc/kurtosis-sync/env`
4. Enables and starts the service

## Configuration

The service uses the following environment variables:

- `VICTORIA_METRICS_URL`: The URL for the VictoriaMetrics API
- `PROMETHEUS_REMOTE_WRITE_USERNAME`: Username for VictoriaMetrics authentication
- `PROMETHEUS_REMOTE_WRITE_PASSWORD`: Password for VictoriaMetrics authentication

These variables are taken from the existing Ansible configuration.

## Systemd Service Management

To manage the service:

```bash
# Status
sudo systemctl status kurtosis-sync

# Restart
sudo systemctl restart kurtosis-sync

# Stop
sudo systemctl stop kurtosis-sync

# View logs
sudo journalctl -u kurtosis-sync -f
```