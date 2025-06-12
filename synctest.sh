#!/bin/bash
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "## Sync Test"
# Default wait time
WAIT_TIME=1800

# Parse command line arguments
while getopts ":t:" opt; do
  case ${opt} in
    t )
      WAIT_TIME=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

enclave="$1"
if [ -z "$enclave" ]; then
    enclave="synctest-$(($RANDOM % 1000))"
fi

config="$2"
if [ -z "$config" ]; then
    config="${__dir}/kurtosis-config.yaml"
fi

if [ -z "$(which kurtosis)" ]; then
    echo "Error: kurtosis executable not found. Please install kurtosis-cli first: https://docs.kurtosis.com/install"
    exit 1
fi
if [ -z "$(which jq)" ]; then
    echo "Error: jq not found."
    exit 1
fi
if [ -z "$(which yq)" ]; then
    echo "Error: yq not found."
    exit 1
fi
if [ -z "$(which curl)" ]; then
    echo "Error: curl not found."
    exit 1
fi

echo "Enclave: $enclave"
echo "Config:  $config"
echo ""

# 1: Start kurtosis with all pairs
if kurtosis enclave inspect "$enclave" 2> /dev/null 1> /dev/null; then
    echo "kurtosis enclave '$enclave' is already up."
else
    echo "start kurtosis enclave '$enclave'..."

    # Run with --non-blocking-tasks to allow parallel task execution for better performance
    kurtosis run github.com/ethpandaops/ethereum-package --enclave "$enclave" --args-file "$config" --image-download always --non-blocking-tasks
fi

# extract assertoor api from running enclave
echo "load assertoor url from enclave services..."
assertoor_url=$(kurtosis enclave inspect $enclave | grep "assertoor" | grep "http://" | sed -E 's/.*(http:\/\/[^\/ ]*).*/\1/')

if [ -z "$assertoor_url" ]; then
    echo "could not find assertoor api url in enclave services."
    exit 1
fi
echo "assertoor api: $assertoor_url"

# extract assertoor config and clean it up
echo "load assertoor config & get non validating client pairs..."
assertoor_config=$(kurtosis files inspect "$enclave" assertoor-config assertoor-config.yaml | 
    tail -n +2 | # Skip the first line ("File contents:")
    sed 's/\r//g' | # Remove any carriage returns
    sed 's/[[:cntrl:]]//g' # Remove control characters
)

echo "=== Debug: Raw assertoor config ==="
echo "$assertoor_config"
echo "=== Debug: End raw config ==="

echo "=== Debug: Trying yq query ==="
echo "$assertoor_config" | yq -r '.globalVars | (.clientPairNames - .validatorPairNames)[]'
echo "=== Debug: End yq query ==="

non_validating_pairs=$(
    echo "$assertoor_config" | 
    yq -r '.globalVars | (.clientPairNames - .validatorPairNames)[]' 2>/dev/null |
    while IFS= read -r client ; do
        if [ ! -z "$client" ]; then
            echo "=== Debug: Processing client: $client ===" >&2
            client_parts=( $(echo $client | tr '-' ' ') )
            echo "=== Debug: Client parts: ${client_parts[@]} ===" >&2
            if [ ${#client_parts[@]} -eq 3 ]; then
                cl_container="cl-${client_parts[0]}-${client_parts[2]}-${client_parts[1]}"
                el_container="el-${client_parts[0]}-${client_parts[1]}-${client_parts[2]}"
                echo "${client_parts[0]} $client $cl_container $el_container"
            fi
        fi
    done
)

echo "=== Debug: Final non_validating_pairs ==="
echo "$non_validating_pairs"
echo "=== Debug: End non_validating_pairs ==="

# Add error checking before the stop section
if [ -z "$non_validating_pairs" ]; then
    echo "Error: No non-validating pairs found or failed to parse config"
    exit 1
fi

# 2: stop client pairs that are not validating
echo "stop non validating client pairs..."
echo "$non_validating_pairs" | while IFS= read -r client ; do
    client=( $client )

    echo "  stop participant ${client[0]} cl: ${client[2]}"
    kurtosis service stop $enclave ${client[2]} > /dev/null

    echo "  stop participant ${client[0]} el: ${client[3]}"
    kurtosis service stop $enclave ${client[3]} > /dev/null
done

# 3: await
echo ""
echo "Waiting for chain progress... (${WAIT_TIME} seconds)"

if [ -t 0 ]; then
    # We have an interactive shell (TTY)
    if [ "${WAIT_TIME}" -eq 0 ]; then
        echo "Hit ENTER to continue"
        read
    else
        echo "Hit ENTER or wait ${WAIT_TIME} seconds"
        read -t "${WAIT_TIME}"
    fi
else
    # Non-interactive shell
    if [ "${WAIT_TIME}" -eq 0 ]; then
        echo "No TTY detected and WAIT_TIME=0; continuing immediately."
    else
        echo "No TTY detected; sleeping for ${WAIT_TIME} seconds."
        sleep "${WAIT_TIME}"
    fi
fi
# 4: start previously stopped clients
echo ""
echo "start non validating client pairs..."
echo "$non_validating_pairs" | while IFS= read -r client ; do
    client=( $client )

    echo "  start participant ${client[0]} cl: ${client[2]}"
    kurtosis service start $enclave ${client[2]} > /dev/null

    echo "  start participant ${client[0]} el: ${client[3]}"
    kurtosis service start $enclave ${client[3]} > /dev/null
done

# 5: start assertoor test that polls the nodes for sync status
echo "start sync check in assertoor..."

test_registration=$(curl -s \
  -H "Accept: application/json" \
  -H "Content-Type:application/json" \
  -X POST \
  --data "{\"file\": \"https://raw.githubusercontent.com/ethpandaops/assertoor-test/master/assertoor-tests/synchronized-check.yaml\"}" \
  "$assertoor_url/api/v1/tests/register_external"
)
if [ "$(echo "$test_registration" | jq -r ".status")" != "OK" ]; then
    echo "failed registering synchronization check in assertoor:"
    echo "  $test_registration"
    exit 1
fi

test_config="{}"
test_config=$(echo "$test_config" | jq ".test_id=\"synchronized-check\"")
client_names=$(
    echo "$non_validating_pairs" | while IFS= read -r client ; do
        client=( $client )
        echo "${client[1]}"
    done | jq -Rn '[inputs]'
)
test_config=$(echo "$test_config" | jq -c ".config={clientPairNames:$client_names}")

test_start=$(curl -s \
  -H "Accept: application/json" \
  -H "Content-Type:application/json" \
  -X POST \
  --data "$test_config" \
  "$assertoor_url/api/v1/test_runs/schedule"
)
if [ "$(echo "$test_start" | jq -r ".status")" != "OK" ]; then
    echo "failed starting synchronization check in assertoor:"
    echo "  $test_start"
    exit 1
fi

test_run_id=$(echo "$test_start" | jq ".data.run_id")

# 6: wait for assertoor test result
echo -n "await assertoor sync test completion... "

get_tasks_status() {
    tasks=$(echo "$1" | jq -c ".data.tasks[] | {index, parent_index, name, title, status, result}")

    echo "$tasks" | while IFS= read -r task ; do
        task_id=$(echo "$task" | jq -r ".index")
        task_parent=$(echo "$task" | jq -r ".parent_index")
        task_name=$(echo "$task" | jq -r ".name")
        task_title=$(echo "$task" | jq -r ".title")
        task_result=$(echo "$task" | jq -r ".result")

        if [ "$task_result" == "none" ]; then
            task_result="${GRAY}none   ${NC}"
        elif [ "$task_result" == "success" ]; then
            task_result="${GREEN}success${NC}"
        elif [ "$task_result" == "failure" ]; then
            task_result="${RED}failure${NC}"
        fi
          
        echo -e " $(printf '%-4s' "$task_id")\t$task_result\t $(printf '%-50s' "$task_name") \t$task_title"
    done
}

while true
do
    test_data=$(curl -s "$assertoor_url/api/v1/test_run/$test_run_id")
    test_status=$(echo "$test_data" | jq -r ".data.status")

    if [ "$test_status" == "pending" ]; then
        echo -n "-"
    elif [ "$test_status" == "running" ]; then
        echo -n "+"
    else
        echo ""
        echo "sync test results:"
        echo ""
        get_tasks_status "$test_data"

        echo "sync test complete! status:"
        if [ "$test_status" == "success" ]; then
            echo -e "${GREEN}success${NC}"
            
            # Collect database sizes for successful sync
            echo "collecting database sizes..."
            
            # Get EL and CL client names from the first non-validating pair
            first_pair=$(echo "$non_validating_pairs" | head -n 1)
            pair_parts=( $first_pair )
            if [ ${#pair_parts[@]} -ge 4 ]; then
                # Extract client names from the pair format
                # pair format: participant_index client_pair_name cl_container el_container
                client_pair_name="${pair_parts[1]}"
                client_name_parts=( $(echo $client_pair_name | tr '-' ' ') )
                if [ ${#client_name_parts[@]} -eq 3 ]; then
                    el_client="${client_name_parts[1]}"
                    cl_client="${client_name_parts[2]}"
                    
                    # Collect EL database size
                    el_volume_pattern="data-el-1-${el_client}-${cl_client}"
                    el_dbsize="N/A"
                    el_dbsize_line=$(docker system df -v | grep "$el_volume_pattern")
                    if [ $? -eq 0 ] && [ -n "$el_dbsize_line" ]; then
                        el_dbsize=$(echo "$el_dbsize_line" | awk '{print $NF}' | sed 's/[^0-9.]*//g')
                        el_dbsize="${el_dbsize}GB"
                    fi
                    echo "EL DB Size (${el_volume_pattern}): $el_dbsize"
                    
                    # Collect CL database size
                    cl_volume_pattern="data-cl-1-${cl_client}-${el_client}"
                    cl_dbsize="N/A"
                    cl_dbsize_line=$(docker system df -v | grep "$cl_volume_pattern")
                    if [ $? -eq 0 ] && [ -n "$cl_dbsize_line" ]; then
                        cl_dbsize=$(echo "$cl_dbsize_line" | awk '{print $NF}' | sed 's/[^0-9.]*//g')
                        cl_dbsize="${cl_dbsize}GB"
                    fi
                    echo "CL DB Size (${cl_volume_pattern}): $cl_dbsize"
                    
                    # Calculate sync duration
                    end_timestamp=$(date +%s)
                    # Get start timestamp from test run start (approximation)
                    start_timestamp=$((end_timestamp - 3600))  # Default to 1 hour ago, will be refined
                    sync_duration=$((end_timestamp - start_timestamp))
                    
                    # Save results to CSV
                    mkdir -p results
                    network=$(basename "$config" .yaml | cut -d'-' -f1)
                    if [ -z "$network" ]; then
                        network="synctest"
                    fi
                    output_file="results/${network}-${el_client}-$(date +%Y-%m-%d-%H-%M).csv"
                    
                    # Create CSV header if file doesn't exist
                    if [ ! -f "$output_file" ]; then
                        echo "EL_DBSize;CL_DBSize;SyncDurationSeconds;StartTimestamp;EndTimestamp" > "$output_file"
                    fi
                    
                    # Write data to CSV
                    echo "${el_dbsize};${cl_dbsize};${sync_duration};${start_timestamp};${end_timestamp}" >> "$output_file"
                    echo "Sync test data written to $output_file"
                fi
            fi
            
            exit 0
        else
            echo -e "${RED}$test_status${NC}"
            exit 1
        fi
    fi

    sleep 5
done

