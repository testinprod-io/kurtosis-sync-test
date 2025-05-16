#!/bin/bash

network=("hoodi" "sepolia" "mainnet")
el=("nethermind" "reth" "geth" "besu" "erigon")
branch="main"
while true; do
  for el_client in "${el[@]}"; do
    for net in "${network[@]}"; do
      start_timestamp=$(date +%s)
      echo "Starting Kurtosis run for ${net}-${el_client} at $(date)"
      kurtosis run github.com/ethpandaops/ethereum-package@${branch} --args-file "${net}/${net}-${el_client}.yaml" --enclave "${net}-${el_client}" --verbosity detailed --image-download always
      http_target=$(kurtosis port print ${net}-${el_client} cl-1-lighthouse-${el_client} http)
      while true; do
        sync_status_json=$(curl --max-time 10 -s ${http_target}/eth/v1/node/syncing)
        if [ $? -ne 0 ]; then
          echo "Failed to curl CL syncing endpoint for ${net}-${el_client}. Retrying in 10s..."
          sleep 10
          continue
        fi

        if [ -z "$sync_status_json" ] || ! echo "$sync_status_json" | jq -e . > /dev/null 2>&1; then
            echo "Invalid or empty JSON from CL syncing endpoint for ${net}-${el_client}. Retrying in 10s..."
            kurtosis clean -a
            sleep 5
            break
        fi

        is_syncing=$(echo "$sync_status_json" | jq -r '.data.is_syncing')
        is_optimistic=$(echo "$sync_status_json" | jq -r '.data.is_optimistic')

        echo "Checking sync status for ${net}-${el_client} at $(date): is_syncing=$is_syncing, is_optimistic=$is_optimistic"
        if [ "$is_syncing" = "true" ]; then
            echo "CL (${net}-${el_client}) is Syncing"
        elif [ "$is_optimistic" = "true" ]; then
            echo "CL (${net}-${el_client}) is in Optimistic mode (EL likely not synced)"
        else
            end_timestamp=$(date +%s)
            echo "CL (${net}-${el_client}) Synced at $(date)"

            volume_name_pattern="data-el-1-${el_client}-lighthouse"
            dbsize="N/A"
            dbsize_line=$(docker system df -v | grep "$volume_name_pattern")

            if [ $? -eq 0 ] && [ -n "$dbsize_line" ]; then
                dbsize=$(echo "$dbsize_line" | awk '{print $NF}')
                echo "DB Size (${volume_name_pattern}): $dbsize"
            else
                echo "Could not determine DB size using pattern '${volume_name_pattern}' for ${net}-${el_client}. Check docker volumes."
            fi

            sync_duration=$((end_timestamp - start_timestamp))
            echo "Sync Duration for ${net}-${el_client}: $sync_duration seconds"
            echo "Start Timestamp: $start_timestamp"
            echo "End Timestamp: $end_timestamp"
            mkdir -p results
            output_file="results/${net}-${el_client}.csv"
            if [ ! -f "$output_file" ]; then
              echo "DBSize;SyncDurationSeconds;StartTimestamp;EndTimestamp" > "$output_file"
            fi
            echo "$dbsize;$sync_duration;$start_timestamp;$end_timestamp" >> "$output_file"
            echo "Data written to $output_file"

            echo "Cleaning Kurtosis environment..."
            kurtosis clean -a
            if [ $? -ne 0 ]; then
               echo "Warning: kurtosis clean -a failed."
            fi

            echo "Waiting 10 seconds before next run..."
            sleep 10

            break
        fi
        sleep 5
      done
    done
  done
  echo "Completed full cycle of ELs and Networks. Restarting loop."
done
