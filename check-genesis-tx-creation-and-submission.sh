#!/usr/bin/env nix-shell
#!nix-shell -i bash -p yj

set -euo pipefail

if ./check-shelley-testnet.sh; then
    echo "Shelley Testnet startup and sanity check returned with success. Preparing generation of genesis transaction file"
    cd cardano-node
    UTXO_STATUS="$(./scripts/issue-genesis-utxo-expenditure.sh genesis-tx-file.bin)"
    echo $UTXO_STATUS
    TX_ID="$(echo $UTXO_STATUS | awk '{ print $2 }')"
    
    SUBMIT_TX_STATUS="$(./scripts/submit-tx.sh genesis-tx-file.bin)"
    echo "SUBMIT_TX_STATUS: ${SUBMIT_TX_STATUS}"
    TMUX_LOG="$(ls -l |grep tmux-server-.*[0-9].log | awk '{ print $9 }')"
    sleep 120
    TX_SUBMISSION_RESULTS="$(grep ${TX_ID} ${TMUX_LOG})"
    echo "TX_SUBMISSION_RESULTS: ${TX_SUBMISSION_RESULTS}"
    tmux kill-server
    exit 0

else
    echo "Error: Shelley Testnet startup and sanity check script returned with error therefore this script will not be run as it depends on Testnet"
    tmux kill-server
    exit 1
fi

