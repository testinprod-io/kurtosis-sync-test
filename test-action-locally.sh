#!/bin/bash
# Script to test GitHub Actions locally using act or direct execution

set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}GitHub Action Local Testing Tool${NC}"
echo "=================================="

# Function to check if act is installed
check_act_installed() {
    if command -v act &> /dev/null; then
        echo -e "${GREEN}✓ act is installed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ act is not installed${NC}"
        echo ""
        echo "To install act:"
        echo "  macOS:    brew install act"
        echo "  Linux:    curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
        echo "  Or visit: https://github.com/nektos/act"
        echo ""
        return 1
    fi
}

# Function to test the setup-matrix job independently
test_setup_matrix() {
    echo -e "\n${BLUE}Testing setup-matrix job...${NC}"
    
    # Create a temporary test script that mimics the GitHub Actions environment
    cat > /tmp/test-setup-matrix.sh << 'EOF'
#!/bin/bash
# Simulate GitHub Actions environment variables
export GITHUB_OUTPUT=/tmp/github_output

# Test inputs
export EL_CLIENTS="${1:-geth,nethermind}"
export CL_CLIENTS="${2:-lighthouse,teku}"
export MATRIX_MODE="${3:-matrix}"
export GITHUB_EVENT_NAME="workflow_dispatch"

echo "Testing with:"
echo "  EL clients: $EL_CLIENTS"
echo "  CL clients: $CL_CLIENTS"
echo "  Matrix mode: $MATRIX_MODE"
echo ""

# Run the setup-matrix logic
set -x

# Parse comma-separated clients
# Convert to arrays
IFS=',' read -ra EL_ARRAY <<< "$EL_CLIENTS"
IFS=',' read -ra CL_ARRAY <<< "$CL_CLIENTS"

# Trim whitespace from each element
for i in "${!EL_ARRAY[@]}"; do
    EL_ARRAY[$i]=$(echo "${EL_ARRAY[$i]}" | xargs)
done
for i in "${!CL_ARRAY[@]}"; do
    CL_ARRAY[$i]=$(echo "${CL_ARRAY[$i]}" | xargs)
done

# Create matrix based on mode
MATRIX_JSON='{"include":['
FIRST=true
TEST_COUNT=0

if [ "$MATRIX_MODE" == "matrix" ]; then
    # Create all combinations
    for el in "${EL_ARRAY[@]}"; do
        for cl in "${CL_ARRAY[@]}"; do
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                MATRIX_JSON+=','
            fi
            MATRIX_JSON+="{\"el_client\":\"$el\",\"cl_client\":\"$cl\"}"
            ((TEST_COUNT++))
        done
    done
else
    # Single test mode - use first of each
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        MATRIX_JSON+=','
    fi
    MATRIX_JSON+="{\"el_client\":\"${EL_ARRAY[0]}\",\"cl_client\":\"${CL_ARRAY[0]}\"}"
    TEST_COUNT=1
fi

MATRIX_JSON+=']}'

echo ""
echo "Generated matrix: $MATRIX_JSON"
echo "matrix=$MATRIX_JSON" >> $GITHUB_OUTPUT
echo "test_count=$TEST_COUNT" >> $GITHUB_OUTPUT

echo ""
echo "GitHub Output:"
cat $GITHUB_OUTPUT
EOF

    chmod +x /tmp/test-setup-matrix.sh
    
    # Test different scenarios
    echo -e "\n${YELLOW}Test 1: Matrix mode with multiple clients${NC}"
    /tmp/test-setup-matrix.sh "geth,nethermind" "lighthouse,teku" "matrix"
    
    echo -e "\n${YELLOW}Test 2: Single mode${NC}"
    /tmp/test-setup-matrix.sh "geth,nethermind,reth" "lighthouse,teku,prysm" "single"
    
    echo -e "\n${YELLOW}Test 3: Single client each${NC}"
    /tmp/test-setup-matrix.sh "geth" "lighthouse" "matrix"
    
    # Clean up
    rm -f /tmp/test-setup-matrix.sh /tmp/github_output
}

# Function to test with act
test_with_act() {
    echo -e "\n${BLUE}Testing with act...${NC}"
    
    # Create test event files
    mkdir -p .github/test-events
    
    # Test event 1: Matrix mode with multiple clients
    cat > .github/test-events/matrix-test.json << 'EOF'
{
  "inputs": {
    "network": "fusaka-devnet-2",
    "el_clients": "geth,nethermind",
    "cl_clients": "lighthouse,teku",
    "matrix_mode": "matrix",
    "wait_time": "60"
  }
}
EOF

    # Test event 2: Single mode test
    cat > .github/test-events/single-test.json << 'EOF'
{
  "inputs": {
    "network": "mainnet",
    "el_clients": "geth",
    "cl_clients": "lighthouse",
    "matrix_mode": "single",
    "wait_time": "1800"
  }
}
EOF

    # Test event 3: Custom network
    cat > .github/test-events/custom-network.json << 'EOF'
{
  "inputs": {
    "network": "custom",
    "custom_network": "my-test-network",
    "el_clients": "reth",
    "cl_clients": "teku",
    "matrix_mode": "single",
    "wait_time": "300"
  }
}
EOF

    echo "Available test scenarios:"
    echo "  1. Matrix test (multiple clients)"
    echo "  2. Single test"
    echo "  3. Custom network test"
    echo ""
    
    read -p "Select test scenario (1-3) or 'all' to run all: " choice
    
    case $choice in
        1)
            echo "Running matrix test..."
            act workflow_dispatch -e .github/test-events/matrix-test.json -W .github/workflows/sync-test.yml --dryrun
            ;;
        2)
            echo "Running single test..."
            act workflow_dispatch -e .github/test-events/single-test.json -W .github/workflows/sync-test.yml --dryrun
            ;;
        3)
            echo "Running custom network test..."
            act workflow_dispatch -e .github/test-events/custom-network.json -W .github/workflows/sync-test.yml --dryrun
            ;;
        all)
            echo "Running all tests..."
            for event in .github/test-events/*.json; do
                echo -e "\n${YELLOW}Testing with $event${NC}"
                act workflow_dispatch -e "$event" -W .github/workflows/sync-test.yml --dryrun
            done
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
}

# Function to test the action.yml directly
test_action_directly() {
    echo -e "\n${BLUE}Testing action.yml directly...${NC}"
    
    # Create a test script that sources the action steps
    cat > /tmp/test-action.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Simulate GitHub Actions environment
export GITHUB_OUTPUT=/tmp/github_output
export GITHUB_STEP_SUMMARY=/tmp/github_step_summary
export GITHUB_RUN_ID="test-$$"
export GITHUB_RUN_NUMBER="1"
export GITHUB_SHA="test-sha"
export GITHUB_REF="refs/heads/test"

# Test inputs
export INPUT_NETWORK="${1:-fusaka-devnet-2}"
export INPUT_EL_CLIENT="${2:-geth}"
export INPUT_CL_CLIENT="${3:-lighthouse}"
export INPUT_WAIT_TIME="${4:-60}"
export INPUT_CLIENT_IMAGES="${5:-{}}"

echo "Testing action with:"
echo "  Network: $INPUT_NETWORK"
echo "  EL Client: $INPUT_EL_CLIENT"
echo "  CL Client: $INPUT_CL_CLIENT"
echo "  Wait Time: $INPUT_WAIT_TIME"
echo ""

# Test config determination logic
echo "Testing config file determination..."

# Simulate the config determination step
if [ -n "$INPUT_CONFIG_FILE" ] && [ "$INPUT_CONFIG_FILE" != "kurtosis-config.yaml" ]; then
    config_file="$INPUT_CONFIG_FILE"
else
    # Check if this is a fusaka devnet
    if [[ "$INPUT_NETWORK" == fusaka-devnet-* ]]; then
        config_file="devnet-templates/devnet-template.yaml"
    else
        # Use network-specific config if available
        network_config="$INPUT_NETWORK/$INPUT_NETWORK-$INPUT_EL_CLIENT.yaml"
        if [ -f "$network_config" ]; then
            config_file="$network_config"
        else
            config_file="kurtosis-config.yaml"
        fi
    fi
fi

echo "Determined config file: $config_file"

# Clean up
rm -f /tmp/github_output /tmp/github_step_summary
EOF

    chmod +x /tmp/test-action.sh
    
    # Test different scenarios
    echo -e "\n${YELLOW}Test 1: fusaka-devnet-2${NC}"
    /tmp/test-action.sh "fusaka-devnet-2" "geth" "lighthouse" "60"
    
    echo -e "\n${YELLOW}Test 2: mainnet${NC}"
    /tmp/test-action.sh "mainnet" "nethermind" "teku" "1800"
    
    echo -e "\n${YELLOW}Test 3: Custom network${NC}"
    /tmp/test-action.sh "my-custom-net" "reth" "prysm" "300"
    
    # Clean up
    rm -f /tmp/test-action.sh
}

# Main menu
echo ""
echo "Select testing method:"
echo "  1. Test setup-matrix job logic"
echo "  2. Test with act (requires act installed)"
echo "  3. Test action.yml logic directly"
echo "  4. Run all tests"
echo ""

read -p "Enter choice (1-4): " main_choice

case $main_choice in
    1)
        test_setup_matrix
        ;;
    2)
        if check_act_installed; then
            test_with_act
        fi
        ;;
    3)
        test_action_directly
        ;;
    4)
        test_setup_matrix
        echo ""
        if check_act_installed; then
            test_with_act
        fi
        echo ""
        test_action_directly
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Testing complete!${NC}"