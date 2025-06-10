# Ethereum Client Sync Test Script

This repository contains a test script that automates the testing of Ethereum clients' ability to synchronize with an existing Ethereum network.

## Dependencies

Before using the script, ensure you have the following dependencies installed:

- [Kurtosis](https://docs.kurtosis.com/install)
- `curl`
- `jq`
- `yq`

## Usage

To start the synchronization test, use the following command:

```sh
make run
```

To stop and clean up the testnet, use:

```sh
make clean
```

Running `make` alone will execute the synchronization test and clean up afterwards.

### Prepare `kurtosis-config.yaml`

Before running the test, ensure that the `kurtosis-config.yaml` file is prepared to include the client pairs that should be tested. 
All participants with `validator_count: 0` are stopped after initialization and tested for their synchronization capabilities later on.

## Parameters

Instead of using `make run`, you can manually invoke the `synctest.sh` script with optional parameters for dev/debugging purposes:

```sh
./synctest.sh <enclave-name> <kurtosis-config>
```

- `<enclave-name>`: Name of the enclave (defaults to `synctest-XXX`, where `XXX` is a random string)
- `<kurtosis-config>`: Path to the Kurtosis configuration file (defaults to `./kurtosis-config.yaml`)

## PeerDAS Sync Test

The `peerdas-sync-test.sh` script is designed to test Consensus Layer (CL) clients' synchronization capabilities on PeerDAS-enabled devnets (default: fusaka-devnet-1).

### Using Different Devnets

By default, the script uses `fusaka-devnet-1`. To test against a different devnet, use the `-d` flag:

```sh
# Test against fusaka-devnet-0
./peerdas-sync-test.sh -d fusaka-devnet-0

# Test against fusaka-devnet-2 with lighthouse
./peerdas-sync-test.sh -c lighthouse -d fusaka-devnet-2

# Using make with a different devnet
make peerdas-test ARGS="-c teku -d fusaka-devnet-0"
```

**Note:** The script uses a single generic template file (`devnet-templates/devnet-template.yaml`) that automatically adapts to the specified devnet.

### Usage

#### Using Make commands

```sh
# Test all CL clients with default settings
make peerdas-test

# Test a specific CL client
make peerdas-test ARGS="-c lighthouse"

# Test with a custom Docker image
make peerdas-test ARGS="-c teku -i consensys/teku:custom-branch"

# Test with a specific EL client
make peerdas-test ARGS="-c lighthouse -e nethermind"

# Test with a different devnet
make peerdas-test ARGS="-d fusaka-devnet-0"

# Use genesis sync instead of checkpoint sync
make peerdas-test ARGS="-c lighthouse --genesis-sync"

# Set a custom timeout
make peerdas-test ARGS="-t 2400"

# Show help
make peerdas-test ARGS="-h"
```

#### Direct script usage

```sh
# Test all CL clients with default settings
./peerdas-sync-test.sh

# Test a specific CL client
./peerdas-sync-test.sh -c lighthouse

# Test with a custom Docker image
./peerdas-sync-test.sh -c teku -i consensys/teku:custom-branch

# Test with a specific EL client (default is geth)
./peerdas-sync-test.sh -c lighthouse -e nethermind

# Test with a different devnet
./peerdas-sync-test.sh -d fusaka-devnet-0

# Use genesis sync instead of checkpoint sync
./peerdas-sync-test.sh -c lighthouse --genesis-sync

# Set a custom timeout (in seconds)
./peerdas-sync-test.sh -t 2400
```

### Options

- `-c <client>`: Test specific CL client (lighthouse, teku, prysm, nimbus, lodestar, grandine)
- `-i <image>`: Use custom Docker image for the CL client
- `-e <client>`: Use specific EL client (geth, nethermind, reth, besu, erigon) (default: geth)
- `-E <image>`: Use custom Docker image for the EL client
- `-d <devnet>`: Specify devnet to use (default: fusaka-devnet-1)
- `-t <timeout>`: Set timeout in seconds (default: 1800)
- `--genesis-sync`: Use genesis sync instead of checkpoint sync (default: checkpoint sync)
- `-h`: Show help message

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

### Test Output

The script will generate a summary report showing:
- Test status for each client (Success/Failed/Timeout)
- Sync time for successful tests
- Failure reasons for failed tests
- Log file locations for debugging failed tests

Failed test logs are saved to the `logs/` directory with the enclave name.

## Script Description

The script performs the following steps:

1. Spins up a Kurtosis testnet using the provided Kurtosis configuration.
2. Immediately after creation, all client pairs without validator keys are shut down.\
   These clients are initialized but not following the chain.
3. Waits for a specified time to allow the testnet to proceed and build blocks.\
   Several transaction and blob spammers are included to add load to the chain.
4. After 30 minutes or when manually proceeding, the previously shut-down clients are turned on again, starting their synchronization with the chain.
5. An assertion test is launched that polls the now synchronizing clients for their synchronization status.
6. When all clients are synchronized, the test succeeds and the script stops execution.

## GitHub Action

This repository also provides a reusable GitHub Action for testing Ethereum client synchronization capabilities using Kurtosis.

### Features

- **Automated Testing**: Test Ethereum execution and consensus layer client pairs
- **Multi-Network Support**: Test on mainnet, sepolia, and hoodi networks
- **Client Flexibility**: Support for multiple EL (Geth, Nethermind, Reth, Besu, Erigon) and CL (Lighthouse, Teku) clients
- **HTML Reports**: Generate beautiful HTML reports for GitHub Pages
- **Configurable**: Flexible configuration for different test scenarios
- **Reusable**: Can be called from other repositories

### Basic Usage

```yaml
- name: Run sync test
  uses: ethpandaops/kurtosis-sync-test@main
  with:
    network: mainnet
    el_client: geth
    cl_client: lighthouse
```

### Advanced Usage

```yaml
- name: Run custom sync test
  uses: ethpandaops/kurtosis-sync-test@main
  with:
    enclave_name: my-custom-test
    config_file: custom-config.yaml
    network: sepolia
    el_client: nethermind
    cl_client: teku
    wait_time: 3600
    generate_html_report: true
    kurtosis_version: 0.89.0
```

### Matrix Testing

```yaml
jobs:
  sync-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        network: [mainnet, sepolia, hoodi]
        el_client: [geth, nethermind, reth]
        cl_client: [lighthouse, teku]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Run sync test
        uses: ethpandaops/kurtosis-sync-test@main
        with:
          network: ${{ matrix.network }}
          el_client: ${{ matrix.el_client }}
          cl_client: ${{ matrix.cl_client }}
```

### Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `enclave_name` | Name for the Kurtosis enclave | No | Auto-generated |
| `config_file` | Path to configuration file | No | `kurtosis-config.yaml` |
| `network` | Network to test (mainnet/sepolia/hoodi) | No | `mainnet` |
| `el_client` | Execution layer client | No | `geth` |
| `cl_client` | Consensus layer client | No | `lighthouse` |
| `wait_time` | Wait time in seconds before restarting clients | No | `1800` |
| `generate_html_report` | Generate HTML report for GitHub Pages | No | `true` |
| `kurtosis_version` | Version of Kurtosis CLI to use | No | `latest` |

### Action Outputs

| Output | Description |
|--------|-------------|
| `test_result` | Result of the sync test (success/failure) |
| `test_summary` | Summary of test execution |
| `html_report_path` | Path to generated HTML report |
| `enclave_name` | Name of the Kurtosis enclave used |

### GitHub Pages Integration

When `generate_html_report` is enabled, the action creates a comprehensive HTML report that can be deployed to GitHub Pages:

```yaml
- name: Setup Pages
  uses: actions/configure-pages@v5

- name: Upload to Pages
  uses: actions/upload-pages-artifact@v3
  with:
    path: reports/

- name: Deploy to GitHub Pages
  uses: actions/deploy-pages@v4
```

### How the Action Works

1. **Setup**: Installs Kurtosis CLI and required dependencies
2. **Validation**: Validates input parameters
3. **Configuration**: Determines the appropriate configuration file
4. **Network Start**: Starts Kurtosis enclave with all client pairs
5. **Client Stop**: Stops non-validating client pairs
6. **Wait Period**: Allows the network to progress
7. **Client Restart**: Restarts stopped clients to test sync
8. **Sync Verification**: Uses Assertoor to verify sync status
9. **Report Generation**: Creates HTML reports and artifacts
10. **Cleanup**: Cleans up Kurtosis resources

### Troubleshooting

**Common Issues:**

1. **Kurtosis Installation Fails**: Ensure the runner has sufficient permissions and internet access
2. **Configuration File Not Found**: Check the path and ensure the file exists in the repository
3. **Sync Test Timeout**: Increase `wait_time` for slower networks
4. **Resource Constraints**: Use `max-parallel` in matrix strategies to limit concurrent tests

**Debug Mode:**

```yaml
- name: Run sync test with debug
  uses: ethpandaops/kurtosis-sync-test@main
  env:
    ACTIONS_STEP_DEBUG: true
    ACTIONS_RUNNER_DEBUG: true
  with:
    network: mainnet
    el_client: geth
    cl_client: lighthouse
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

For more detailed information, refer to the script comments and the [Kurtosis ethereum-package documentation](https://github.com/ethpandaops/ethereum-package).

Feel free to open issues or submit pull requests if you find any bugs or have improvements.

Happy testing!