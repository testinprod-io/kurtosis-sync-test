#!/bin/bash

network=("mainnet")
el=("nethermind" "reth" "geth" "besu" "erigon")
cl=("teku")
branch="main"
# VictoriaMetrics endpoint
VICTORIA_METRICS_URL=${VICTORIA_METRICS_URL:-"https://victoriametrics-public.analytics.production.platform.ethpandaops.io/insert/1/prometheus/api/v1/write"}
# Authentication - these will be set by Ansible
VM_USERNAME=${PROMETHEUS_REMOTE_WRITE_USERNAME:-""}
VM_PASSWORD=${PROMETHEUS_REMOTE_WRITE_PASSWORD:-""}

# Function to send metrics to VictoriaMetrics
send_metric() {
  local metric_name=$1
  local value=$2
  local timestamp=$3

  echo "Sending metric ${metric_name}=${value} to VictoriaMetrics"

  # Create a temporary file with the metric in Prometheus format
  TMPFILE=$(mktemp)
  echo "${metric_name} ${value} ${timestamp}" > "${TMPFILE}"

  # Send using the /api/v1/import/prometheus endpoint which accepts plain text
  # This avoids the need for Snappy compression required by the remote_write endpoint
  curl -s -X POST \
    --user "${VM_USERNAME}:${VM_PASSWORD}" \
    "${VICTORIA_METRICS_URL%/api/v1/write}/api/v1/import/prometheus" \
    --data-binary @"${TMPFILE}"

  # Clean up
  rm "${TMPFILE}"
}

kurtosis clean -a
while true; do
  for el_client in "${el[@]}"; do
    for net in "${network[@]}"; do
      start_timestamp=$(date +%s)
      enclave_name="${net}-${el_client}"
      echo "Starting Kurtosis run for ${enclave_name} at $(date)"

      # Send start sync metric
      send_metric "${enclave_name}_start_sync_time" "${start_timestamp}" "${start_timestamp}"

      kurtosis run github.com/ethpandaops/ethereum-package@${branch} --args-file "${net}/${net}-${el_client}.yaml" --enclave "${enclave_name}" --verbosity detailed --image-download always
      http_target=$(kurtosis port print ${enclave_name} cl-1-${cl}-${el_client} http)
      while true; do
        sync_status_json=$(curl --max-time 10 -s ${http_target}/eth/v1/node/syncing)
        if [ $? -ne 0 ]; then
          echo "Failed to curl CL syncing endpoint for ${enclave_name}. Retrying in 10s..."
          sleep 10
          continue
        fi

        if [ -z "$sync_status_json" ] || ! echo "$sync_status_json" | jq -e . > /dev/null 2>&1; then
            echo "Invalid or empty JSON from CL syncing endpoint for ${enclave_name}. Retrying in 10s..."
            kurtosis clean -a
            sleep 5
            break
        fi

        is_syncing=$(echo "$sync_status_json" | jq -r '.data.is_syncing')
        is_optimistic=$(echo "$sync_status_json" | jq -r '.data.is_optimistic')

        echo "Checking sync status for ${enclave_name} at $(date): is_syncing=$is_syncing, is_optimistic=$is_optimistic"
        if [ "$is_syncing" = "true" ]; then
            echo "CL (${enclave_name}) is Syncing"
        elif [ "$is_optimistic" = "true" ]; then
            echo "CL (${enclave_name}) is in Optimistic mode (EL likely not synced)"
        else
            end_timestamp=$(date +%s)
            echo "CL (${enclave_name}) Synced at $(date)"

            # Send finished sync metric
            send_metric "${enclave_name}_finished_sync_time" "${end_timestamp}" "${end_timestamp}"

            volume_name_pattern="data-el-1-${el_client}-${cl}"
            dbsize="N/A"
            dbsize_line=$(docker system df -v | grep "$volume_name_pattern")

            if [ $? -eq 0 ] && [ -n "$dbsize_line" ]; then
                dbsize=$(echo "$dbsize_line" | awk '{print $NF}')
                echo "DB Size (${volume_name_pattern}): $dbsize"
            else
                echo "Could not determine DB size using pattern '${volume_name_pattern}' for ${enclave_name}. Check docker volumes."
            fi

            sync_duration=$((end_timestamp - start_timestamp))
            echo "Sync Duration for ${enclave_name}: $sync_duration seconds"
            echo "Start Timestamp: $start_timestamp"
            echo "End Timestamp: $end_timestamp"
            mkdir -p results
            output_file="results/${enclave_name}.csv"
            if [ ! -f "$output_file" ]; then
              echo "DBSize;SyncDurationSeconds;StartTimestamp;EndTimestamp" > "$output_file"
            fi
            echo "$dbsize;$sync_duration;$start_timestamp;$end_timestamp" >> "$output_file"
            echo "Data written to $output_file"
            sleep 30 # sleep to allow prometheus to scrape metrics
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
