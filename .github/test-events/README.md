# GitHub Action Test Events

This directory contains test event JSON files for locally testing the GitHub Actions workflow using `act`.

## Prerequisites

Install `act` to run GitHub Actions locally:
- macOS: `brew install act`
- Linux: `curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash`
- Or visit: https://github.com/nektos/act

## Usage

### Quick Test
```bash
# Use the provided test script
./test-action-locally.sh
```

### Direct Testing with act

```bash
# Test matrix mode with multiple clients
act workflow_dispatch -e .github/test-events/matrix-test.json -W .github/workflows/sync-test.yml

# Test single mode
act workflow_dispatch -e .github/test-events/single-test.json -W .github/workflows/sync-test.yml

# Test with custom network
act workflow_dispatch -e .github/test-events/custom-network.json -W .github/workflows/sync-test.yml

# Dry run (see what would be executed)
act workflow_dispatch -e .github/test-events/matrix-test.json -W .github/workflows/sync-test.yml --dryrun

# Run with specific job
act -j setup-matrix workflow_dispatch -e .github/test-events/matrix-test.json -W .github/workflows/sync-test.yml
```

## Test Scenarios

### 1. matrix-test.json
Tests matrix mode with multiple EL and CL clients, creating all combinations.

### 2. single-test.json
Tests single mode with one EL/CL pair.

### 3. custom-network.json
Tests custom network input option.

### 4. fusaka-devnet.json
Tests fusaka-devnet-2 network configuration.

### 5. scheduled-run.json
Simulates a scheduled workflow run.

## Creating New Test Events

Create a new JSON file with the workflow inputs:

```json
{
  "inputs": {
    "network": "network-name",
    "el_clients": "comma,separated,clients",
    "cl_clients": "comma,separated,clients",
    "matrix_mode": "matrix|single",
    "wait_time": "seconds",
    "custom_network": "optional-custom-name",
    "client_images": "{\"optional\":\"image-overrides\"}"
  }
}
```

## Debugging Tips

1. Use `--verbose` flag for detailed output
2. Use `--dryrun` to see what would be executed
3. Use `-j job-name` to run specific jobs
4. Check `.github/workflows/sync-test.yml` for job names