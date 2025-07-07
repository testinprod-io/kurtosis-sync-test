#!/bin/bash
# Exit on error (-e), undefined variable (-u), and pipe failure (-o pipefail)
set -euo pipefail

# Get the directory where this script is located
# This ensures paths are relative to the script location, not where it's run from
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output formatting
# These ANSI escape codes provide colored terminal output
YELLOW='\033[1;33m'    # Warning messages
GRAY='\033[0;37m'      # Subdued text
GREEN='\033[0;32m'     # Success messages
RED='\033[0;31m'       # Error messages
BLUE='\033[0;34m'      # Headers and info
NC='\033[0m'           # No Color - resets to default

# Default configuration values
DEVNET="${DEVNET:-fusaka-devnet-2}"                              # Default devnet name (can be overridden)
DEVNET_REPO="ethpandaops"                                         # Default devnet repo name (can be overridden)
WAIT_TIME=1800                                                    # Default timeout in seconds (30 minutes)
SPECIFIC_CLIENT=""                                                # Specific CL client to test (empty = test all)
CUSTOM_CL_IMAGE=""                                                # Custom Docker image for CL client
SPECIFIC_EL=""                                                    # Specific EL client to use
CUSTOM_EL_IMAGE=""                                               # Custom Docker image for EL client
TEMPLATE_FILE="${__dir}/devnet-templates/devnet-template.yaml"   # Generic Kurtosis config template
TEMP_CONFIG="/tmp/${DEVNET}-config-$$.yaml"                     # Temporary config file with PID suffix
LOGS_DIR="${__dir}/logs"                                         # Directory to save failure logs
GENESIS_SYNC=false                                               # Use genesis sync instead of checkpoint sync
ALWAYS_COLLECT_LOGS=false                                        # Always collect logs even on success

# List of supported Consensus Layer (CL) clients to test
CL_CLIENTS="lighthouse teku prysm nimbus lodestar grandine"

# List of supported Execution Layer (EL) clients that can be paired with CL clients
EL_CLIENTS="geth nethermind reth besu erigon"

# Function to get default Docker image for a CL client
# Each client has a specific PeerDAS-enabled image version
# Returns the appropriate ethpandaops Docker image for the given CL client
get_default_image() {
    case "$1" in
        "lighthouse") echo "ethpandaops/lighthouse:fusaka-devnet-2" ;;              # Lighthouse fusaka-devnet-2
        "teku") echo "ethpandaops/teku:fusaka-devnet-2" ;;                    # Teku fusaka-devnet-2
        "prysm") echo "ethpandaops/prysm-beacon-chain:fusaka-devnet-2" ;;        # Prysm fusaka-devnet-2
        "nimbus") echo "ethpandaops/nimbus-eth2:fusaka-devnet-2" ;;      # Nimbus fusaka-devnet-2
        "lodestar") echo "ethpandaops/lodestar:fusaka-devnet-2" ;;                   # Lodestar fusaka-devnet-2
        "grandine") echo "ethpandaops/grandine:fusaka-devnet-2" ;;      # Grandine fusaka-devnet-2
        *) echo "" ;;                                                          # Return empty for unknown clients
    esac
}

# Function to get default Docker image for an EL client
# Each EL client has a specific devnet compatible image
# Returns the appropriate ethpandaops Docker image for the given EL client
get_default_el_image() {
    case "$1" in
        "geth") echo "ethpandaops/geth:fusaka-devnet-2" ;;                    # Geth fusaka-devnet-2
        "nethermind") echo "ethpandaops/nethermind:fusaka-devnet-2" ;;               # Nethermind fusaka-devnet-2
        "reth") echo "ethpandaops/reth:fusaka-devnet-2" ;;                     # Reth fusaka-devnet-2
        "besu") echo "ethpandaops/besu:fusaka-devnet-2" ;;            # Besu fusaka-devnet-2
        "erigon") echo "ethpandaops/erigon:fusaka-devnet-2" ;;        # Erigon fusaka-devnet-2
        *) echo "ethpandaops/geth:fusaka-devnet-2" ;;                         # Default to geth if unknown
    esac
}

# Results storage using parallel arrays
# These arrays store test results for final reporting
# Each index corresponds to one test run
TEST_CLIENTS=()    # Client names (lighthouse, teku, etc.)
TEST_RESULTS=()    # Test outcomes (Success, Failed, Timeout, Unknown)
TEST_TIMES=()      # Time taken for each test
TEST_NOTES=()      # Additional notes or failure reasons
TEST_LOG_PATHS=()  # Paths to log directories for failed tests

# Display help information about script usage
# Shows all available options and provides usage examples
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Test CL client sync capability on ${DEVNET} network"
    echo ""
    echo "Options:"
    echo "  -c <client>    Test specific CL client (lighthouse, teku, prysm, nimbus, lodestar, grandine)"
    echo "  -i <image>     Use custom Docker image for the CL client"
    echo "  -e <client>    Use specific EL client (geth, nethermind, reth, besu, erigon) (default: geth)"
    echo "  -E <image>     Use custom Docker image for the EL client"
    echo "  -d <devnet>    Specify devnet to use (default: fusaka-devnet-2)"
    echo "  -D <devnet_repo>    Specify devnet repo to use (default: ethpandaops)"
    echo "  -t <timeout>   Set timeout in seconds (default: 1800)"
    echo "  --genesis-sync Use genesis sync instead of checkpoint sync (default: checkpoint sync)"
    echo "  --always-collect-logs Always collect enclave logs (even on success)"
    echo "  -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test all CL clients with default settings"
    echo "  $0 -c lighthouse                      # Test only Lighthouse with default geth"
    echo "  $0 -c teku -i consensys/teku:develop  # Test Teku with custom image"
    echo "  $0 -e nethermind                      # Test all CL clients with Nethermind"
    echo "  $0 -c lighthouse -e reth              # Test Lighthouse with Reth"
    echo "  $0 -t 2400                             # Test with custom timeout"
    echo "  $0 -c lighthouse -e nethermind         # Test Lighthouse with Nethermind"
    echo "  $0 -c teku -e besu -E hyperledger/besu:develop  # Test Teku with custom Besu image"
    echo "  $0 -c lighthouse --genesis-sync      # Test Lighthouse with genesis sync"
    echo "  $0 -c lighthouse -d your_devnet -D your_devnet_repo # Test Lighthouse with network config from your custom devnet repo"
    exit 0
}

# Parse command line arguments using getopts
# Supported options:
# -c: Specific CL client to test
# -i: Custom CL client Docker image
# -e: Specific EL client to use
# -E: Custom EL client Docker image
# -d: Devnet to use
# -t: Timeout in seconds
# -h: Show help
# --genesis-sync: Use genesis sync instead of checkpoint sync
# --always-collect-logs: Always collect logs even on success
# First, handle long options
for arg in "$@"; do
    if [[ "$arg" == "--genesis-sync" ]]; then
        GENESIS_SYNC=true
        # Remove the processed long option from arguments
        set -- "${@/$arg/}"
    elif [[ "$arg" == "--always-collect-logs" ]]; then
        ALWAYS_COLLECT_LOGS=true
        # Remove the processed long option from arguments
        set -- "${@/$arg/}"
    fi
done

while getopts ":c:i:e:E:d:D:t:h" opt; do
    case ${opt} in
        c )  # CL client selection
            SPECIFIC_CLIENT=$OPTARG
            # Validate that the provided client is in our supported list
            if [[ ! " $CL_CLIENTS " =~ " $SPECIFIC_CLIENT " ]]; then
                echo "Error: Unknown CL client '$SPECIFIC_CLIENT'"
                echo "Valid CL clients: $CL_CLIENTS"
                exit 1
            fi
            ;;
        i )  # Custom CL Docker image
            CUSTOM_CL_IMAGE=$OPTARG
            ;;
        e )  # EL client selection
            SPECIFIC_EL=$OPTARG
            # Validate that the provided EL client is in our supported list
            if [[ ! " $EL_CLIENTS " =~ " $SPECIFIC_EL " ]]; then
                echo "Error: Unknown EL client '$SPECIFIC_EL'"
                echo "Valid EL clients: $EL_CLIENTS"
                exit 1
            fi
            ;;
        E )  # Custom EL Docker image
            CUSTOM_EL_IMAGE=$OPTARG
            ;;
        d )  # Devnet selection
            DEVNET=$OPTARG
            ;;
        D ) # Devnet selection
            DEVNET_REPO=$OPTARG
            ;;
        t )  # Timeout value in seconds
            WAIT_TIME=$OPTARG
            ;;
        h )  # Help option
            show_help
            ;;
        \? )  # Invalid option provided
            echo "Invalid option: -$OPTARG" 1>&2
            show_help
            ;;
        : )  # Option requires an argument but none provided
            echo "Option -$OPTARG requires an argument" 1>&2
            exit 1
            ;;
    esac
done
# Remove processed options from the argument list
shift $((OPTIND -1))

# Check for required tools before running tests
# This function verifies all necessary command-line tools are installed
# Exits with error if any required tool is missing
check_requirements() {
    local missing_tools=()  # Array to collect names of missing tools
    
    # Check for kurtosis - orchestrates Ethereum network setup
    if ! command -v kurtosis &> /dev/null; then
        missing_tools+=("kurtosis")
    fi
    
    # Check for jq - parses JSON responses from APIs
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    # Check for yq - processes YAML configuration files
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    # Check for curl - makes HTTP requests to services
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    # Check for envsubst - substitutes environment variables in templates
    if ! command -v envsubst &> /dev/null; then
        missing_tools+=("envsubst (gettext)")
    fi
    
    # Exit if any tools are missing
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# Generate Kurtosis configuration from template
# Substitutes client types, images, and network settings into the YAML template
# Parameters:
#   $1: CL client type (lighthouse, teku, etc.)
#   $2: CL client Docker image
#   $3: EL client type (geth, nethermind, etc.)
#   $4: EL client Docker image
generate_config() {
    local cl_type="$1"    # Consensus layer client type
    local cl_image="$2"   # Docker image for CL client
    local el_type="$3"    # Execution layer client type  
    local el_image="$4"   # Docker image for EL client
    
    # NAT configuration removed - no longer needed
    
    # Export variables for template substitution
    export CL_CLIENT_TYPE="$cl_type"
    export CL_CLIENT_IMAGE="$cl_image"
    export EL_CLIENT_TYPE="$el_type"
    export EL_CLIENT_IMAGE="$el_image"
    export DEVNET="$DEVNET"
    export DEVNET_REPO="$DEVNET_REPO"
    # Set checkpoint sync based on GENESIS_SYNC flag
    if [ "$GENESIS_SYNC" = true ]; then
        export CHECKPOINT_SYNC="false"
    else
        export CHECKPOINT_SYNC="true"
    fi
    
    # Substitute template variables and create temporary config file
    envsubst '$CL_CLIENT_TYPE $CL_CLIENT_IMAGE $EL_CLIENT_TYPE $EL_CLIENT_IMAGE $CHECKPOINT_SYNC $DEVNET $DEVNET_REPO' < "$TEMPLATE_FILE" > "$TEMP_CONFIG"
}

# Helper function to extract runtime from task data and format it
# Parameters:
#   $1: test_data JSON
#   $2: task name to extract runtime for
# Returns: Formatted time string (e.g., "5m 30s") or "N/A"
extract_task_runtime() {
    local test_data="$1"
    local task_name="$2"
    
    local runtime=$(echo "$test_data" | jq -r ".data.tasks[] | select(.name == \"$task_name\") | .runtime" 2>/dev/null || echo "")
    
    if [ -n "$runtime" ] && [ "$runtime" != "null" ] && [ "$runtime" != "0" ]; then
        # Convert milliseconds to minutes and seconds
        local minutes=$((runtime / 60000))
        local seconds=$(((runtime % 60000) / 1000))
        echo "${minutes}m ${seconds}s"
    else
        echo "N/A"
    fi
}

# Add test result to arrays for final reporting
# Stores test outcome data in parallel arrays
# Parameters:
#   $1: Client name (e.g., "lighthouse")
#   $2: Test result (Success/Failed/Timeout/Unknown)
#   $3: Time taken for the test
#   $4: Additional notes or failure reason
#   $5: Log directory path (optional, for failed tests)
add_test_result() {
    local client="$1"    # Name of the tested client
    local result="$2"    # Test outcome
    local time="$3"      # Duration of test
    local note="$4"      # Any additional information
    local log_path="$5"  # Path to logs (for failures)
    
    # Append to result arrays
    TEST_CLIENTS+=("$client")
    TEST_RESULTS+=("$result")
    TEST_TIMES+=("$time")
    TEST_NOTES+=("$note")
    TEST_LOG_PATHS+=("$log_path")
}

# Save logs and configuration
# Collects all relevant logs for debugging
# Parameters:
#   $1: Client name
#   $2: Kurtosis enclave name
#   $3: Path to config file used
# Returns: Prints the absolute path to the log directory
save_failure_logs() {
    local client="$1"       # Client being tested
    local enclave="$2"      # Kurtosis enclave containing the test
    local config_file="$3"  # Configuration file used for this test
    
    # Create logs directory structure for this test
    local enclave_log_dir="${LOGS_DIR}/${enclave}"
    mkdir -p "$enclave_log_dir"
    
    echo -e "${YELLOW}Saving logs and config...${NC}" >&2
    
    # Save the Kurtosis config file used for this test
    if [ -f "$config_file" ]; then
        cp "$config_file" "${enclave_log_dir}/config.yaml"
        echo "Config saved to: ${enclave_log_dir}/config.yaml" >&2
        
        # Also print the config to console for immediate visibility
        echo -e "\n${YELLOW}=== Configuration used ===${NC}" >&2
        cat "$config_file" >&2
        echo -e "${YELLOW}=== End of configuration ===${NC}\n" >&2
    fi

    # Save kurtosis startup logs if they exist
    if [ -f "/tmp/kurtosis-${client}.log" ]; then
        cp "/tmp/kurtosis-${client}.log" "${enclave_log_dir}/kurtosis-startup.log"
        echo "Kurtosis startup log saved to: ${enclave_log_dir}/kurtosis-startup.log" >&2
    fi
    
    # Dump entire enclave state and logs (includes all service logs)
    echo "Collecting enclave logs..." >&2
    
    # Check if enclave exists before trying to dump
    if kurtosis enclave inspect "$enclave" &>/dev/null; then
        # Try to dump the enclave, capturing any errors
        # Kurtosis requires the dump directory to not exist, so we create a subdirectory
        local dump_dir="${enclave_log_dir}/enclave-dump"
        local dump_command="kurtosis enclave dump $enclave ${dump_dir}"
        echo "Running: $dump_command" >&2
        
        local dump_output
        dump_output=$(kurtosis enclave dump $enclave ${dump_dir} 2>&1)
        local dump_exit_code=$?
        
        if [ $dump_exit_code -eq 0 ]; then
            echo "Enclave dump completed successfully" >&2
        else
            echo "Warning: Enclave dump had issues (exit code: $dump_exit_code)" >&2
            echo "Command was: $dump_command" >&2
            echo "Dump output: $dump_output" >&2
            # Even if dump fails, we may have partial logs which is better than nothing
        fi
    else
        echo "Warning: Enclave '$enclave' not found or already removed" >&2
        echo "This can happen if the test cleanup was very fast" >&2
    fi
    
    echo -e "${YELLOW}All logs saved to: ${enclave_log_dir}${NC}" >&2
    
    # Return the absolute path to the log directory
    echo "$(cd "$enclave_log_dir" && pwd)"
}

# Test a single CL client's sync capability
# This is the main test function that:
# 1. Starts a Kurtosis enclave with the specified clients
# 2. Registers and runs a sync test via Assertoor
# 3. Monitors test progress until completion or timeout
# Parameters:
#   $1: CL client name
#   $2: CL client Docker image
#   $3: EL client name
#   $4: EL client Docker image
test_client() {
    local client="$1"      # CL client to test
    local image="$2"       # Docker image for CL client
    local el_type="$3"     # EL client type to pair with
    local el_image="$4"    # Docker image for EL client
    local enclave="peerdas-sync-${client}-$(date +%s)"  # Unique enclave name with timestamp
    local start_time=$(date +%s)  # Track test duration
    local client_pair="${client}-${el_type}"  # Combined client name for reporting
    
    echo -e "\n${BLUE}=== Testing ${client} with ${el_type} (images: ${image}, ${el_image}) ===${NC}"
    
    # Generate Kurtosis config file from template with current test parameters
    generate_config "$client" "$image" "$el_type" "$el_image"
    
    # Start Kurtosis enclave with the ethereum-package
    echo "Starting Kurtosis enclave: $enclave"
    # Run ethereum-package with:
    # --enclave: unique name for this test instance
    # --args-file: config file with client specifications
    # --image-download always: ensure latest images are used
    # --non-blocking-tasks: don't wait for long-running tasks
    if ! kurtosis run github.com/ethpandaops/ethereum-package \
        --enclave "$enclave" \
        --args-file "$TEMP_CONFIG" \
        --image-download always \
        --non-blocking-tasks > /tmp/kurtosis-${client}.log 2>&1; then
        
        echo -e "${RED}Failed to start Kurtosis enclave${NC}"
        
        # Save logs for debugging the failure and get log path
        local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
        add_test_result "$client_pair" "Failed" "N/A" "Kurtosis startup failed" "$log_path"
        
        # Cleanup enclave after logs are collected
        echo "Cleaning up failed enclave..."
        kurtosis enclave stop "$enclave" 2>/dev/null || true
        kurtosis enclave rm "$enclave" 2>/dev/null || true
        
        # Remove temp config and continue to next test
        rm -f "$TEMP_CONFIG"
        return 0
    fi
    
    # Wait for services to initialize and become ready
    # This gives time for all containers to start and establish connections
    echo "Waiting for services to initialize..."
    sleep 30
    
    # Extract Assertoor service URL using kurtosis port print
    # Assertoor is the testing framework that validates sync status
    local assertoor_url=$(kurtosis port print "$enclave" assertoor http 2>/dev/null)
    
    # Check if Assertoor service is available
    if [ -z "$assertoor_url" ]; then
        echo -e "${RED}Could not find assertoor URL${NC}"
        
        # Save logs on failure and get log path
        local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
        add_test_result "$client_pair" "Failed" "N/A" "Assertoor not available" "$log_path"
        
        # Cleanup enclave after logs are collected
        echo "Cleaning up failed enclave..."
        kurtosis enclave stop "$enclave" 2>/dev/null || true
        kurtosis enclave rm "$enclave" 2>/dev/null || true
        
        # Remove temp config and continue to next test
        rm -f "$TEMP_CONFIG"
        return 0
    fi
    
    echo "Assertoor URL: $assertoor_url"
    
    # Register the synchronization test with Assertoor
    # This loads the test definition from the assertoor-test repository
    echo "Registering sync test in assertoor..."
    local test_registration=$(curl -s \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -X POST \
        --data "{\"file\": \"https://raw.githubusercontent.com/ethpandaops/assertoor-test/master/assertoor-tests/synchronized-check.yaml\"}" \
        "$assertoor_url/api/v1/tests/register_external" 2>/dev/null)
    
    # Verify test registration was successful
    if [ "$(echo "$test_registration" | jq -r ".status" 2>/dev/null)" != "OK" ]; then
        echo -e "${RED}Failed to register sync test${NC}"
        
        # Save logs on failure and get log path
        local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
        add_test_result "$client_pair" "Failed" "N/A" "Test registration failed" "$log_path"
        
        # Cleanup enclave after logs are collected
        echo "Cleaning up failed enclave..."
        kurtosis enclave stop "$enclave" 2>/dev/null || true
        kurtosis enclave rm "$enclave" 2>/dev/null || true
        
        # Remove temp config and continue to next test
        rm -f "$TEMP_CONFIG"
        return 0
    fi
    
    # Configure and start the sync test
    # The test config specifies which client pair to test
    # Format: "1-<el_type>-<cl_type>" where 1 is the node index
    local test_config='{"test_id":"synchronized-check","config":{"clientPairNames":["1-'${el_type}'-'${client}'"]}}'
    # Schedule the sync test to run
    local test_start=$(curl -s \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -X POST \
        --data "$test_config" \
        "$assertoor_url/api/v1/test_runs/schedule" 2>/dev/null)
    
    # Verify test was scheduled successfully
    if [ "$(echo "$test_start" | jq -r ".status" 2>/dev/null)" != "OK" ]; then
        echo -e "${RED}Failed to start sync test${NC}"
        
        # Save logs on failure and get log path
        local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
        add_test_result "$client_pair" "Failed" "N/A" "Test start failed" "$log_path"
        
        # Cleanup enclave after logs are collected
        echo "Cleaning up failed enclave..."
        kurtosis enclave stop "$enclave" 2>/dev/null || true
        kurtosis enclave rm "$enclave" 2>/dev/null || true
        
        # Remove temp config and continue to next test
        rm -f "$TEMP_CONFIG"
        return 0
    fi
    
    # Extract test run ID for monitoring
    local test_run_id=$(echo "$test_start" | jq -r ".data.run_id")
    echo "Started sync test with ID: $test_run_id"
    
    # Monitor test progress until completion or timeout
    echo -n "Monitoring sync progress"
    local timeout_counter=0      # Tracks elapsed time in seconds
    local test_complete=false    # Flag to indicate test completion
    
    # Poll test status until completion or timeout
    while [ $timeout_counter -lt $WAIT_TIME ]; do
        # Fetch current test status from Assertoor API
        local test_data=$(curl -s "$assertoor_url/api/v1/test_run/$test_run_id" 2>/dev/null)
        local test_status=$(echo "$test_data" | jq -r ".data.status" 2>/dev/null)
        
        # Handle different test statuses
        case "$test_status" in
            "pending"|"running")
                # Test still in progress - print progress indicator
                echo -n "."
                ;;
            "success")
                # Test passed - client successfully synced
                echo -e "\n${GREEN}Sync test completed successfully!${NC}"
                
                # Extract runtime from task data
                local total_time=$(extract_task_runtime "$test_data" "run_task_matrix")
                
                # Always collect logs if flag is set
                if [ "$ALWAYS_COLLECT_LOGS" = true ]; then
                    local log_output=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG")
                    local log_path=$(echo "$log_output" | tail -1)
                    add_test_result "$client_pair" "Success" "$total_time" "" "$log_path"
                else
                    add_test_result "$client_pair" "Success" "$total_time" "" ""
                fi
                test_complete=true
                break
                ;;
            "failure")
                # Test failed - extract and record failure reason
                echo -e "\n${RED}Sync test failed${NC}"
                # Extract failure reason from the first failed task
                local failure_reason=$(echo "$test_data" | jq -r '.data.tasks[] | select(.result == "failure") | .title' 2>/dev/null | head -1)
                
                # Extract runtime from task data
                local total_time=$(extract_task_runtime "$test_data" "run_task_matrix")
                
                # Save logs on failure and get log path
                local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
                add_test_result "$client_pair" "Failed" "$total_time" "${failure_reason:-Unknown failure}" "$log_path"
                
                test_complete=true
                break
                ;;
            *)
                # Unexpected test status - treat as failure
                echo -e "\n${YELLOW}Unknown test status: $test_status${NC}"
                
                # Extract runtime from task data
                local total_time=$(extract_task_runtime "$test_data" "run_task_matrix")
                
                # Save logs on failure and get log path
                local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
                add_test_result "$client_pair" "Unknown" "$total_time" "Unknown status: $test_status" "$log_path"
                
                test_complete=true
                break
                ;;
        esac
        
        # Wait 5 seconds before next status check
        sleep 5
        ((timeout_counter+=5))  # Increment timeout counter
    done
    
    # Handle timeout case - test didn't complete within time limit
    if [ "$test_complete" = false ]; then
        echo -e "\n${RED}Test timed out after ${WAIT_TIME} seconds${NC}"
        
        # Try to get final test data for timeout case
        local test_data=$(curl -s "$assertoor_url/api/v1/test_run/$test_run_id" 2>/dev/null)
        
        # Extract runtime from task data
        local total_time=$(extract_task_runtime "$test_data" "run_task_matrix")
        
        # Save logs on failure and get log path
        local log_path=$(save_failure_logs "$client" "$enclave" "$TEMP_CONFIG" | tail -1)
        add_test_result "$client_pair" "Timeout" "$total_time" "Exceeded ${WAIT_TIME}s timeout" "$log_path"
    fi
    
    # Cleanup after test
    echo "Cleaning up enclave..."
    # Clean up the enclave after all logs have been collected
    kurtosis enclave stop "$enclave" 2>/dev/null || true
    kurtosis enclave rm "$enclave" 2>/dev/null || true
    
    # Remove temporary config file
    rm -f "$TEMP_CONFIG"
    
    return 0
}

# Generate summary report of all test results
# Creates a formatted table showing test outcomes for all clients
# Sets appropriate exit code based on success rate
generate_report() {
    # Print report header
    echo -e "\n${BLUE}=============================================="
    echo "PeerDAS Sync Test Results for ${DEVNET}"
    echo -e "==============================================${NC}\n"
    
    # Table header with column labels
    echo -e "Client Pair Test Results:"
    printf "%-20s | %-8s | %-10s | %s\n" "CL-EL Pair" "Status" "Total Time" "Notes"
    printf "%-20s---%-8s---%-10s---%s\n" "--------------------" "--------" "----------" "-----"
    
    # Track success statistics
    local success_count=0
    local total_count=0
    
    # Iterate through all test results
    for i in "${!TEST_CLIENTS[@]}"; do
        local client="${TEST_CLIENTS[$i]}"
        local status="${TEST_RESULTS[$i]}"
        local time="${TEST_TIMES[$i]}"
        local notes="${TEST_NOTES[$i]}"
        local log_path="${TEST_LOG_PATHS[$i]}"
        
        # Apply color coding based on test status and count successes
        case "$status" in
            "Success")
                success_count=$((success_count + 1))  # Increment success counter
                ;;
        esac
        
        # Print formatted row for this client
        printf "%-20s | %-8s | %-10s | %s\n" "$client" "$status" "$time" "$notes"
        
        # If we have a log path, show it
        if [[ -n "$log_path" ]]; then
            printf "%-20s   %-8s   %-10s   %s\n" "" "" "" "Logs: $log_path"
        fi
        
        total_count=$((total_count + 1))
    done
    
    # Print summary statistics
    echo -e "\nSummary: ${success_count}/${total_count} clients successfully synced"

    # Exit with appropriate code
    # Check if we have any results at all
    if [ $total_count -eq 0 ]; then
        echo -e "\n${RED}ERROR: No test results were recorded!${NC}"
        echo "This usually means the test results were not properly captured."
        exit 1
    elif [ $success_count -eq $total_count ]; then
        # All tests passed
        exit 0
    else
        # Some tests failed
        exit 1
    fi
}

# Main execution function
# Orchestrates the entire test process:
# 1. Validates environment and dependencies
# 2. Determines which clients to test
# 3. Runs tests for each client
# 4. Generates final report
main() {
    # Print header
    echo -e "${BLUE}PeerDAS Sync Test for ${DEVNET}${NC}"
    echo "======================================="
    
    # Create logs directory if it doesn't exist
    mkdir -p "$LOGS_DIR"
    
    # Verify all required tools are installed
    check_requirements
    
    # Determine which clients to test based on command line args
    local clients_to_test=()
    
    if [ -n "$SPECIFIC_CLIENT" ]; then
        # Test only the specified client
        clients_to_test=("$SPECIFIC_CLIENT")
    else
        # Test all supported CL clients
        clients_to_test=($CL_CLIENTS)
    fi
    
    echo "Testing clients: ${clients_to_test[*]}"
    echo "Timeout per client: ${WAIT_TIME} seconds"
    echo "Always collect logs: ${ALWAYS_COLLECT_LOGS}"
    
    # Determine EL client to use (defaults to geth if not specified)
    local el_type="${SPECIFIC_EL:-geth}"
    local el_image
    if [ -n "$CUSTOM_EL_IMAGE" ]; then
        # Use custom EL image if provided
        el_image="$CUSTOM_EL_IMAGE"
    else
        # Use default image for the selected EL client
        el_image=$(get_default_el_image "$el_type")
    fi
    
    echo "Using EL client: ${el_type}"
    
    # Run test for each CL client
    for client in "${clients_to_test[@]}"; do
        local image
        # Use custom image if provided for the specific client
        if [ -n "$CUSTOM_CL_IMAGE" ] && [ "$client" = "$SPECIFIC_CLIENT" ]; then
            image="$CUSTOM_CL_IMAGE"
        else
            # Use default image for the client
            image=$(get_default_image "$client")
        fi
        # Execute the test for this client
        test_client "$client" "$image" "$el_type" "$el_image"
    done
    
    # Generate final report and set exit code
    generate_report
}

# Entry point - run the main function
main