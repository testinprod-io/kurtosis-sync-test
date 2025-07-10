# Ethereum Client Sync Test

This repository contains automated testing infrastructure for Ethereum clients' synchronization capabilities using [Kurtosis](https://docs.kurtosis.com/). The primary focus is on testing PeerDAS-enabled devnets and various client combinations.

## Overview

The sync test framework:
- Tests Ethereum execution layer (EL) and consensus layer (CL) client pairs
- Verifies clients can successfully sync with an existing network
- Supports custom Docker images for testing development branches
- Provides detailed test reports and logs
- Includes reusable GitHub Actions for CI/CD integration

## Dependencies

Before using the test scripts, ensure you have the following dependencies installed:

- [Kurtosis](https://docs.kurtosis.com/install)
- `curl`
- `jq`
- `yq`
- `docker`

## PeerDAS Sync Test

The `peerdas-sync-test.sh` script tests Consensus Layer (CL) clients' synchronization capabilities on PeerDAS-enabled devnets.

### Quick Start

```sh
# Test all CL clients
./peerdas-sync-test.sh

# Test specific CL client
./peerdas-sync-test.sh -c lighthouse

# Using make
make peerdas-test
make peerdas-test ARGS="-c teku"
```

### Options

- `-c <client>`: Test specific CL client (lighthouse, teku, prysm, nimbus, lodestar, grandine)
- `-i <image>`: Use custom Docker image for the CL client
- `-e <client>`: Use specific EL client (geth, nethermind, reth, besu, erigon) (default: geth)
- `-E <image>`: Use custom Docker image for the EL client
- `-d <devnet>`: Specify devnet to use (default: fusaka-devnet-2)
- `-D <devnet_repo>`: Specify devnet repo to use (default: ethpandaops)
- `-t <timeout>`: Set timeout in seconds (default: 1800)
- `--genesis-sync`: Use genesis sync instead of checkpoint sync (default: checkpoint sync)
- `--always-collect-logs`: Always collect enclave logs (even on success)
- `--supernode`: Enable supernode functionality for participants
- `-h`: Show help message

### Examples

```sh
# Test with custom Docker image
./peerdas-sync-test.sh -c teku -i consensys/teku:custom-branch

# Test with specific EL client
./peerdas-sync-test.sh -c lighthouse -e nethermind

# Test with longer timeout
./peerdas-sync-test.sh -t 2400

# Test with genesis sync
./peerdas-sync-test.sh -c lighthouse --genesis-sync

# Test with supernode enabled
./peerdas-sync-test.sh -c lighthouse --supernode

# Test with custom devnet and repo
./peerdas-sync-test.sh -c lighthouse -d your_devnet -D your_devnet_repo

# Test with always collecting logs
./peerdas-sync-test.sh -c teku --always-collect-logs

# Test with custom EL image
./peerdas-sync-test.sh -c teku -e besu -E hyperledger/besu:develop
```

### Supported Clients

**Consensus Layer (CL) clients:**
- Lighthouse
- Teku
- Prysm
- Nimbus
- Lodestar
- Grandine

**Execution Layer (EL) clients:**
- Geth (default)
- Nethermind
- Reth
- Besu
- Erigon

## Test Process

The test script performs the following steps:

1. **Network Setup**: Spins up a Kurtosis enclave with the specified client configuration
2. **Client Initialization**: Starts all clients and waits for network initialization
3. **Client Shutdown**: Stops non-validating clients after initialization
4. **Network Progress**: Allows the network to progress and produce blocks (default: 30 minutes)
5. **Sync Test**: Restarts stopped clients to test synchronization
6. **Verification**: Uses Assertoor to verify successful synchronization
7. **Reporting**: Generates test reports and saves logs for failed tests

## Configuration

The test framework uses a generic template approach with environment variable substitution:

- **Template**: `devnet-templates/devnet-template.yaml`
- **Variables**: Automatically populated based on selected devnet and client options
- **Customization**: The template adapts to different networks and client combinations

## Test Output

The script generates comprehensive test reports including:
- Test status for each client (Success/Failed/Timeout)
- Sync time for successful tests
- Failure reasons and error details
- Log file locations for debugging

Failed test logs are saved to the `logs/` directory with the enclave name for debugging.

## GitHub Action

This repository provides a reusable GitHub Action for automated testing in CI/CD pipelines.

### Basic Usage

```yaml
- name: Run sync test
  uses: ethpandaops/kurtosis-sync-test@main
  with:
    el_client: geth
    cl_client: lighthouse
```

### Advanced Usage

```yaml
- name: Run custom sync test
  uses: ethpandaops/kurtosis-sync-test@main
  with:
    enclave_name: my-custom-test
    el_client: nethermind
    cl_client: teku
    wait_time: 3600
    kurtosis_version: 0.89.0
```

### Matrix Testing

```yaml
jobs:
  sync-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        el_client: [geth, nethermind, reth]
        cl_client: [lighthouse, teku, prysm]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Run sync test
        uses: ethpandaops/kurtosis-sync-test@main
        with:
          el_client: ${{ matrix.el_client }}
          cl_client: ${{ matrix.cl_client }}
```

### Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `enclave_name` | Name for the Kurtosis enclave | No | Auto-generated |
| `el_client` | Execution layer client | No | `geth` |
| `cl_client` | Consensus layer client | No | `lighthouse` |
| `wait_time` | Wait time in seconds before restarting clients | No | `1800` |
| `kurtosis_version` | Version of Kurtosis CLI to use | No | `latest` |

### Action Outputs

| Output | Description |
|--------|-------------|
| `test_result` | Result of the sync test (success/failure) |
| `test_summary` | Summary of test execution |
| `enclave_name` | Name of the Kurtosis enclave used |

## Development

### Project Structure

```
.
├── peerdas-sync-test.sh      # Main test script
├── devnet-templates/         # Generic configuration templates
├── action.yml               # GitHub Action definition
├── .github/
│   ├── workflows/          # CI/CD workflows
│   └── scripts/           # Helper scripts
└── logs/                 # Test logs (generated)
```

### Running Tests Locally

1. Clone the repository
2. Install dependencies
3. Run tests:
   ```sh
   make peerdas-test
   ```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
