#!/bin/bash

  network=("hoodi")
  el=("geth" "reth")

while true; do
  start_timestamp=$(date +%s)
  for el in ${el[@]}; do
    for network in ${network[@]}; do
      kurtosis run github.com/ethpandaops/ethereum-package@bbusa/add-force-snapshot --args-file ${network}/${network}-${el}.yaml --enclave ${network}-${el} --verbosity detailed --image-download always
      while true; do

        is_syncing=$(curl -s localhost:33001/eth/v1/node/syncing | jq -r '.data.is_syncing')
        is_optimistic=$(curl -s localhost:33001/eth/v1/node/syncing | jq -r '.data.is_optimistic')

        if [ "$is_syncing" = "true" ]; then
            echo "CL is Syncing"
        elif [ "$is_optimistic" = "true" ]; then
            echo "CL is in Optimistic mode, means EL is not synced"
        else
            end_timestamp=$(date +%s)
            echo "Synced"
            dbsize=$(docker system df -v | grep data-el-1-geth-lighthouse | awk '{print $NF}')
            echo "DB Size: $dbsize"
            sync_duration=$((end_timestamp - start_timestamp))
            echo "Sync Duration for ${network}-${el}: $sync_duration seconds"
            echo "Start Timestamp: $start_timestamp"
            echo "End Timestamp: $end_timestamp"
            echo "$dbsize;$sync_duration" >> ${network}-${el}-$(date +%Y-%m-%d-%H-%M).txt
            kurtosis clean -a
            break
        fi
        sleep 5
      done
    done
  done
done
