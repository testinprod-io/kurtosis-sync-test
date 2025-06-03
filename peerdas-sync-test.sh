#!/bin/bash
set -euo pipefail

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
WAIT_TIME=1800
SPECIFIC_CLIENT=""
CUSTOM_IMAGE=""
SPECIFIC_EL=""
CUSTOM_EL_IMAGE=""
TEMPLATE_FILE="${__dir}/fusaka-devnet-0/fusaka-devnet-0-template.yaml"
TEMP_CONFIG="/tmp/fusaka-devnet-0-config-$$.yaml"
LOGS_DIR="${__dir}/logs"

# List of supported CL clients
CL_CLIENTS="lighthouse teku prysm nimbus lodestar grandine"

# List of supported EL clients
EL_CLIENTS="geth nethermind reth besu erigon"

# Function to get default image for a client
get_default_image() {
    case "$1" in
        "lighthouse") echo "ethpandaops/lighthouse:eip-7892" ;;
        "teku") echo "ethpandaops/teku:master-7856340" ;;
        "prysm") echo "ethpandaops/prysm-beacon-chain:peerdas-bpo" ;;
        "nimbus") echo "ethpandaops/nimbus-eth2:bpo-parsing-c62f33f" ;;
        "lodestar") echo "ethpandaops/lodestar:peerDAS" ;;
        "grandine") echo "ethpandaops/grandine:peerdas-fulu-a0df259" ;;
        *) echo "" ;;
    esac
}

# Function to get default EL image for a client
get_default_el_image() {
    case "$1" in
        "geth") echo "ethpandaops/geth:fusaka-devnet-0" ;;
        "nethermind") echo "ethpandaops/nethermind:devnet-0" ;;
        "reth") echo "ethpandaops/reth:fusaka-devnet0" ;;
        "besu") echo "ethpandaops/besu:fusaka-devnet-0-ed8ec22" ;;
        "erigon") echo "ethpandaops/erigon:fusaka-devnet-0-ed36f15" ;;
        *) echo "ethpandaops/geth:fusaka-devnet-0" ;;
    esac
}

# Results storage (using parallel arrays)
TEST_CLIENTS=()
TEST_RESULTS=()
TEST_TIMES=()
TEST_NOTES=()

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Test CL client sync capability on fusaka-devnet-0 network"
    echo ""
    echo "Options:"
    echo "  -c <client>    Test specific CL client (lighthouse, teku, prysm, nimbus, lodestar, grandine)"
    echo "  -i <image>     Use custom Docker image for the CL client"
    echo "  -e <client>    Use specific EL client (geth, nethermind, reth, besu, erigon) (default: geth)"
    echo "  -E <image>     Use custom Docker image for the EL client"
    echo "  -t <timeout>   Set timeout in seconds (default: 1800)"
    echo "  -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test all CL clients with default geth"
    echo "  $0 -c lighthouse                      # Test only Lighthouse with default geth"
    echo "  $0 -c teku -i consensys/teku:develop  # Test Teku with custom image"
    echo "  $0 -e nethermind                      # Test all CL clients with Nethermind"
    echo "  $0 -c lighthouse -e reth              # Test Lighthouse with Reth"
    echo "  $0 -c teku -e besu -E hyperledger/besu:develop  # Test Teku with custom Besu image"
    exit 0
}

# Parse command line arguments
while getopts ":c:i:e:E:t:h" opt; do
    case ${opt} in
        c )
            SPECIFIC_CLIENT=$OPTARG
            if [[ ! " $CL_CLIENTS " =~ " $SPECIFIC_CLIENT " ]]; then
                echo "Error: Unknown CL client '$SPECIFIC_CLIENT'"
                echo "Valid CL clients: $CL_CLIENTS"
                exit 1
            fi
            ;;
        i )
            CUSTOM_IMAGE=$OPTARG
            ;;
        e )
            SPECIFIC_EL=$OPTARG
            if [[ ! " $EL_CLIENTS " =~ " $SPECIFIC_EL " ]]; then
                echo "Error: Unknown EL client '$SPECIFIC_EL'"
                echo "Valid EL clients: $EL_CLIENTS"
                exit 1
            fi
            ;;
        E )
            CUSTOM_EL_IMAGE=$OPTARG
            ;;
        t )
            WAIT_TIME=$OPTARG
            ;;
        h )
            show_help
            ;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            show_help
            ;;
        : )
            echo "Option -$OPTARG requires an argument" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Check for required tools
check_requirements() {
    local missing_tools=()
    
    if ! command -v kurtosis &> /dev/null; then
        missing_tools+=("kurtosis")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v envsubst &> /dev/null; then
        missing_tools+=("envsubst (gettext)")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# Generate config from template
generate_config() {
    local cl_type="$1"
    local cl_image="$2"
    local el_type="$3"
    local el_image="$4"
    
    # Get external IP
    local nat_exit_ip=$(curl -s https://icanhazip.com || echo "")
    if [ -z "$nat_exit_ip" ]; then
        echo -e "${YELLOW}Warning: Could not fetch external IP, using empty value${NC}"
        nat_exit_ip=""
    else
        echo "Using NAT exit IP: $nat_exit_ip"
    fi
    
    export CL_CLIENT_TYPE="$cl_type"
    export CL_CLIENT_IMAGE="$cl_image"
    export EL_CLIENT_TYPE="$el_type"
    export EL_CLIENT_IMAGE="$el_image"
    export NAT_EXIT_IP="$nat_exit_ip"
    
    envsubst '$CL_CLIENT_TYPE $CL_CLIENT_IMAGE $EL_CLIENT_TYPE $EL_CLIENT_IMAGE $NAT_EXIT_IP' < "$TEMPLATE_FILE" > "$TEMP_CONFIG"
}

# Add test result to arrays
add_test_result() {
    local client="$1"
    local result="$2"
    local time="$3"
    local note="$4"
    
    TEST_CLIENTS+=("$client")
    TEST_RESULTS+=("$result")
    TEST_TIMES+=("$time")
    TEST_NOTES+=("$note")
}

# Save logs and config on failure
save_failure_logs() {
    local client="$1"
    local enclave="$2"
    local config_file="$3"
    
    # Create logs directory structure
    local enclave_log_dir="${LOGS_DIR}/${enclave}"
    mkdir -p "$enclave_log_dir"
    
    echo -e "${YELLOW}Saving logs and config for failed test...${NC}"
    
    # Save the config file
    if [ -f "$config_file" ]; then
        cp "$config_file" "${enclave_log_dir}/config.yaml"
        echo "Config saved to: ${enclave_log_dir}/config.yaml"
        
        # Also print the config
        echo -e "\n${YELLOW}=== Configuration used ===${NC}"
        cat "$config_file"
        echo -e "${YELLOW}=== End of configuration ===${NC}\n"
    fi
    
    # Save kurtosis logs
    if [ -f "/tmp/kurtosis-${client}.log" ]; then
        cp "/tmp/kurtosis-${client}.log" "${enclave_log_dir}/kurtosis-startup.log"
        echo "Kurtosis startup log saved to: ${enclave_log_dir}/kurtosis-startup.log"
    fi
    
    # Get enclave logs
    echo "Collecting enclave logs..."
    kurtosis enclave dump "$enclave" "${enclave_log_dir}" 2>/dev/null || echo "Failed to dump enclave logs"
    
    # Get service logs
    echo "Collecting service logs..."
    local services=$(kurtosis enclave inspect "$enclave" 2>/dev/null | grep -E "cl-|el-|assertoor" | awk '{print $1}' || true)
    for service in $services; do
        echo "Getting logs for $service..."
        kurtosis service logs "$enclave" "$service" > "${enclave_log_dir}/${service}.log" 2>&1 || true
    done
    
    echo -e "${YELLOW}All logs saved to: ${enclave_log_dir}${NC}"
}

# Test a single CL client
test_client() {
    local client="$1"
    local image="$2"
    local el_type="$3"
    local el_image="$4"
    local enclave="peerdas-sync-${client}-$(date +%s)"
    local start_time=$(date +%s)
    
    echo -e "\n${BLUE}=== Testing ${client} with image ${image} ===${NC}"
    echo "Using EL client: ${el_type} with image ${el_image}"
    
    # Generate config
    generate_config "$client" "$image" "$el_type" "$el_image"
    
    # Start kurtosis
    echo "Starting Kurtosis enclave: $enclave"
    if ! kurtosis run github.com/ethpandaops/ethereum-package \
        --enclave "$enclave" \
        --args-file "$TEMP_CONFIG" \
        --image-download always \
        --non-blocking-tasks > /tmp/kurtosis-${client}.log 2>&1; then
        
        echo -e "${RED}Failed to start Kurtosis enclave${NC}"
        add_test_result "$client" "Failed" "N/A" "Kurtosis startup failed"
        
        # Save logs on failure
        save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
        
        # Cleanup
#        kurtosis enclave stop "$enclave" 2>/dev/null || true
#        kurtosis enclave rm "$enclave" 2>/dev/null || true
        return 1
    fi
    
    # Wait for services to be ready
    echo "Waiting for services to initialize..."
    sleep 30
    
    # Get assertoor URL
    local assertoor_url=$(kurtosis enclave inspect "$enclave" 2>/dev/null | grep "assertoor" | grep "http://" | sed -E 's/.*(http:\/\/[^\/ ]*).*/\1/' | head -1)
    
    if [ -z "$assertoor_url" ]; then
        echo -e "${RED}Could not find assertoor URL${NC}"
        add_test_result "$client" "Failed" "N/A" "Assertoor not available"
        
        # Save logs on failure
        save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
        
        # Cleanup
#        kurtosis enclave stop "$enclave" 2>/dev/null || true
#        kurtosis enclave rm "$enclave" 2>/dev/null || true
        return 1
    fi
    
    echo "Assertoor URL: $assertoor_url"
    
    # Register sync test
    echo "Registering sync test in assertoor..."
    local test_registration=$(curl -s \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -X POST \
        --data "{\"file\": \"https://raw.githubusercontent.com/ethpandaops/assertoor-test/master/assertoor-tests/synchronized-check.yaml\"}" \
        "$assertoor_url/api/v1/tests/register_external" 2>/dev/null)
    
    if [ "$(echo "$test_registration" | jq -r ".status" 2>/dev/null)" != "OK" ]; then
        echo -e "${RED}Failed to register sync test${NC}"
        add_test_result "$client" "Failed" "N/A" "Test registration failed"
        
        # Save logs on failure
        save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
        
        # Cleanup
#        kurtosis enclave stop "$enclave" 2>/dev/null || true
#        kurtosis enclave rm "$enclave" 2>/dev/null || true
        return 1
    fi
    
    # Start sync test
    local test_config='{"test_id":"synchronized-check","config":{"clientPairNames":["cl-1-'${client}'-'${el_type}'","el-1-'${el_type}'-'${client}'"]}}'
    local test_start=$(curl -s \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -X POST \
        --data "$test_config" \
        "$assertoor_url/api/v1/test_runs/schedule" 2>/dev/null)
    
    if [ "$(echo "$test_start" | jq -r ".status" 2>/dev/null)" != "OK" ]; then
        echo -e "${RED}Failed to start sync test${NC}"
        add_test_result "$client" "Failed" "N/A" "Test start failed"
        
        # Save logs on failure
        save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
        
        # Cleanup
#        kurtosis enclave stop "$enclave" 2>/dev/null || true
#        kurtosis enclave rm "$enclave" 2>/dev/null || true
        return 1
    fi
    
    local test_run_id=$(echo "$test_start" | jq -r ".data.run_id")
    echo "Started sync test with ID: $test_run_id"
    
    # Monitor test progress
    echo -n "Monitoring sync progress"
    local timeout_counter=0
    local test_complete=false
    
    while [ $timeout_counter -lt $WAIT_TIME ]; do
        local test_data=$(curl -s "$assertoor_url/api/v1/test_run/$test_run_id" 2>/dev/null)
        local test_status=$(echo "$test_data" | jq -r ".data.status" 2>/dev/null)
        
        # Calculate current test duration
        local current_time=$(date +%s)
        local duration=$((current_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        case "$test_status" in
            "pending"|"running")
                echo -n "."
                ;;
            "success")
                echo -e "\n${GREEN}Sync test completed successfully!${NC}"
                add_test_result "$client" "Success" "${minutes}m ${seconds}s" ""
                test_complete=true
                break
                ;;
            "failure")
                echo -e "\n${RED}Sync test failed${NC}"
                # Extract failure reason
                local failure_reason=$(echo "$test_data" | jq -r '.data.tasks[] | select(.result == "failure") | .title' 2>/dev/null | head -1)
                add_test_result "$client" "Failed" "${minutes}m ${seconds}s" "${failure_reason:-Unknown failure}"
                
                # Save logs on failure
                save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
                
                test_complete=true
                break
                ;;
            *)
                echo -e "\n${YELLOW}Unknown test status: $test_status${NC}"
                add_test_result "$client" "Unknown" "${minutes}m ${seconds}s" "Unknown status: $test_status"
                
                # Save logs on failure
                save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
                
                test_complete=true
                break
                ;;
        esac
        
        sleep 5
        ((timeout_counter+=5))
    done
    
    if [ "$test_complete" = false ]; then
        echo -e "\n${RED}Test timed out after ${WAIT_TIME} seconds${NC}"
        add_test_result "$client" "Timeout" "${minutes}m ${seconds}s" "Exceeded ${WAIT_TIME}s timeout"
        
        # Save logs on failure
        save_failure_logs "$client" "$enclave" "$TEMP_CONFIG"
    fi
    
    # Final timing calculation if not already done
    if [ "$test_complete" = false ]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
    fi
    
    # Cleanup
    echo "Cleaning up enclave..."
#    kurtosis enclave stop "$enclave" 2>/dev/null || true
#    kurtosis enclave rm "$enclave" 2>/dev/null || true
    
    # Remove temp config
    rm -f "$TEMP_CONFIG"
    
    return 0
}

# Generate summary report
generate_report() {
    echo -e "\n${BLUE}=============================================="
    echo "PeerDAS Sync Test Results for fusaka-devnet-0"
    echo -e "==============================================${NC}\n"
    
    echo -e "Consensus Layer Clients:"
    printf "%-12s | %-8s | %-10s | %s\n" "Client" "Status" "Sync Time" "Notes"
    printf "%-12s-+-%-8s-+-%-10s-+-%s\n" "------------" "--------" "----------" "-----"
    
    local success_count=0
    local total_count=0
    
    for i in "${!TEST_CLIENTS[@]}"; do
        local client="${TEST_CLIENTS[$i]}"
        local status="${TEST_RESULTS[$i]}"
        local time="${TEST_TIMES[$i]}"
        local notes="${TEST_NOTES[$i]}"
        
        # Color code status
        case "$status" in
            "Success")
                status_colored="${GREEN}${status}${NC}"
                ((success_count++))
                ;;
            "Failed")
                status_colored="${RED}${status}${NC}"
                ;;
            "Timeout")
                status_colored="${YELLOW}${status}${NC}"
                ;;
            *)
                status_colored="${GRAY}${status}${NC}"
                ;;
        esac
        
        printf "%-12s | %-8b | %-10s | %s\n" "$client" "$status_colored" "$time" "$notes"
        ((total_count++))
    done
    
    echo -e "\nSummary: ${success_count}/${total_count} clients successfully synced"
    
    # Exit with appropriate code
    if [ $success_count -eq $total_count ]; then
        exit 0
    else
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}PeerDAS Sync Test for fusaka-devnet-0${NC}"
    echo "======================================="
    
    # Create logs directory if it doesn't exist
    mkdir -p "$LOGS_DIR"
    
    # Check requirements
    check_requirements
    
    # Determine which clients to test
    local clients_to_test=()
    
    if [ -n "$SPECIFIC_CLIENT" ]; then
        clients_to_test=("$SPECIFIC_CLIENT")
    else
        # Test all clients
        clients_to_test=($CL_CLIENTS)
    fi
    
    echo "Testing clients: ${clients_to_test[*]}"
    echo "Timeout per client: ${WAIT_TIME} seconds"
    
    # Determine EL client to use
    local el_type="${SPECIFIC_EL:-geth}"
    local el_image
    if [ -n "$CUSTOM_EL_IMAGE" ]; then
        el_image="$CUSTOM_EL_IMAGE"
    else
        el_image=$(get_default_el_image "$el_type")
    fi
    
    echo "Using EL client: ${el_type}"
    
    # Test each client
    for client in "${clients_to_test[@]}"; do
        local image
        if [ -n "$CUSTOM_IMAGE" ] && [ "$client" = "$SPECIFIC_CLIENT" ]; then
            image="$CUSTOM_IMAGE"
        else
            image=$(get_default_image "$client")
        fi
        test_client "$client" "$image" "$el_type" "$el_image"
    done
    
    # Generate report
    generate_report
}

# Run main function
main