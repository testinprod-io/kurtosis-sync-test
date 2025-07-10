# Kurtosis Sync Test

Automated testing framework for validating Ethereum client synchronization capabilities. This project tests whether Ethereum execution and consensus layer client pairs can successfully sync with an existing blockchain across mainnet, sepolia, and hoodi networks.

## Project Structure
Claude MUST read the `.cursor/rules/project_architecture.mdc` file before making any structural changes to the project.

## Code Standards  
Claude MUST read the `.cursor/rules/code_standards.mdc` file before writing any code in this project.

## Development Workflow
Claude MUST read the `.cursor/rules/development_workflow.mdc` file before making changes to build, test, or deployment configurations.

## Component Documentation
Individual components have their own CLAUDE.md files with component-specific rules. Always check for and read component-level documentation when working on specific parts of the codebase.

## Key Project Information

### Purpose
This project provides automated synchronization testing for Ethereum clients by:
1. Spinning up test networks using Kurtosis
2. Stopping non-validating clients after initialization
3. Allowing the network to produce blocks
4. Restarting clients to test sync capabilities
5. Validating sync status using Assertoor
6. Collecting and reporting performance metrics

### Main Scripts
- `synctest.sh`: Core sync test orchestration (supports `-s` flag for supernode testing)
- `peerdas-sync-test.sh`: PeerDAS sync test with supernode support (`--supernode` flag)
- `oneliner.sh`: Continuous testing loop for all client combinations
- `Makefile`: Simple interface for common operations (includes `run-supernode` target)

### Supported Networks
- Mainnet
- Sepolia
- Hoodi

### Supported Clients
- **Execution Layer**: Geth, Nethermind, Reth, Besu, Erigon
- **Consensus Layer**: Lighthouse, Teku

### Important Considerations
- Always validate YAML syntax before committing configuration changes
- Test scripts with shellcheck before committing
- Ensure proper error handling in all bash scripts
- Never commit credentials or sensitive information
- Follow the established directory structure for network configurations

### Supernode Testing
The project supports supernode functionality for participants through:
- `synctest.sh -s`: Enable supernode for sync testing
- `peerdas-sync-test.sh --supernode`: Enable supernode for PeerDAS testing
- `make run-supernode`: Make target for supernode testing
- GitHub Actions workflow parameter: `supernode_enabled: true`

Supernode configuration adds the `supernode: true` parameter to participant configurations, enabling enhanced networking capabilities for testing purposes.